# -*- coding: utf-8 -*-

from pyqt_import import QtWidgets
import sys,os,re
from main_form.MainForm import MainForm
from misc.ModConfigParser import ModConfigParser
from misc.default_config import BLANK_CHARS,DEFAULT_TEMPLATE


def split_text(mainform):
    # title_tags : [(tag,title)] , tag: h1-h6
    # chapter_list : [main_text]
    title_tags, chapter_list = mainform.split_text()
    lv_to_rule = mainform.name_rule_dict["lv_to_rule"]
    rule_to_preproc = mainform.name_rule_dict["rule_to_preproc"]
    rule_to_txtfragment = mainform.name_rule_dict["rule_to_txtfragment"]

    existed_id_dict = {}
    existed_basename_dict = {}
    for mid,href in bk.text_iter():
        basename = href.lower().split("/")[-1]
        basename = basename.split(".")[0]
        existed_basename_dict[basename.lower()] = True
        unique_id = bk.href_to_id(href)
        if unique_id:
            existed_id_dict[unique_id.lower()] = True

    def li2lowTuple(l:list[str]) -> tuple[str, ...]:
        new_ = []
        for v in l:
            new_.append(v.lower())
        return tuple(new_)
    # 防重名思路：现存的所有文件名提取出来并转化为规则预处理的普通字符串片段格式，
    # 如果转化后的普通字符串片段中存在着与当前预处理普通字符串片段重复的组，则重点处理该组的变量
    # 把改组最后一个序号变量的起始值提高到最大，保证递增后不会再重复


    existed_txtfragments = {li2lowTuple(fgm): 0 for rule, fgm in rule_to_txtfragment.items()}
    for basename in existed_basename_dict.keys():
        text_fragments = li2lowTuple(re.split(r"\d+", basename))
        if existed_txtfragments.get(text_fragments,None) is None:
            continue
        num = re.findall(r"\d+", basename)[-1]
        num = int(num)
        if existed_txtfragments[text_fragments] < num:
            existed_txtfragments[text_fragments] = num

    rule_to_processed = {}  # 用于储存每个规则对应的变量内容
    for rule, preproc in rule_to_preproc.items():
        rule_to_processed[rule] = []
        for i in range(len(preproc)):
            var_sign = preproc[i]
            if type(var_sign) == str:
                rule_to_processed[rule].append("")
            elif type(var_sign) == int:
                start_order = 0
                if i == len(preproc) - 1:
                    fragments = li2lowTuple(rule_to_txtfragment[rule])
                    start_order = existed_txtfragments[fragments]
                rule_to_processed[rule].append(start_order)

    # 开始计算每个文件名
    filename_list = []
    lv_to_lastname = {}
    default_rule = lv_to_rule["default"]
    last_rule = ""
    last_tag = ""
    for tag,title in title_tags:
        rule = lv_to_rule.get(tag,default_rule)
        filename = ""
        for i in range(len(rule_to_preproc[rule])):
            if type(rule_to_processed[rule][i]) == str:
                h_ = rule_to_preproc[rule][i]
                if h_ != tag:
                    rule_to_processed[rule][i] = lv_to_lastname.get(h_,"")
                else:
                    rule_to_processed[rule][i] = ""
                filename += rule_to_txtfragment[rule][i] + rule_to_processed[rule][i]
            elif type(rule_to_processed[rule][i]) == int:
                # $$$ 变量判断归零逻辑：
                # 上一个规则与当前规则不同，且上一个 head 级别 < 当前 head 级别
                L = 0
                if rule_to_preproc[rule][i] < 0:
                    if last_rule != rule and last_tag < tag:
                        rule_to_processed[rule][i] = 0
                    rule_to_processed[rule][i] += 1
                    L = -rule_to_preproc[rule][i]
                else:
                    rule_to_processed[rule][i] += 1
                    L = rule_to_preproc[rule][i]
                order_str =  str(rule_to_processed[rule][i])
                order_str = "0"*(L-len(order_str)) + order_str if len(order_str) < L else order_str
                filename += rule_to_txtfragment[rule][i] + order_str
        filename += rule_to_txtfragment[rule][-1]
        filename_list.append(filename)
        lv_to_lastname[tag] = filename
        last_rule = rule
        last_tag = tag


    unique_filename_list = [] # 二次防重名，防止极端规则书写导致的重名
    count = 1
    for filename in filename_list:
        if existed_basename_dict.get(filename.lower(),None):
            new_name = filename + "_" + str(count)
            while existed_basename_dict.get(new_name.lower(), None):
                count += 1
                new_name = filename + "_" + str(count)
            unique_filename_list.append(new_name)
            existed_basename_dict[new_name.lower()] = True
        else:
            unique_filename_list.append(filename)
            existed_basename_dict[filename.lower()] = True

    unique_filename_list = [filename + ".xhtml" for filename in unique_filename_list]
    unique_id_list = []
    count = 1
    for filename in unique_filename_list:
        if existed_id_dict.get(filename.lower(),None) is None:
            unique_id_list.append(filename)
        else:
            new_id = "X" + str(count) + "_" + filename
            while existed_id_dict.get(new_id.lower(),None):
                count += 1
                new_id = "X" + str(count) + "_" + filename
            unique_id_list.append(new_id)

    return (title_tags, chapter_list, unique_filename_list, unique_id_list)

def build_xhtml(mainform):
    title_tags, chapter_list, filename_list, unique_id_list = split_text(mainform)
    bk_spine = bk.getspine_epub3()

    template_dict = {}
    indent_dict = {}
    for i in [0] + mainform.activated_tpt:
        template_file = f'template/template_{i}.txt'

        with open(template_file,'r',encoding='utf-8') as f:
            template_dict[i] = f.read()

    for lv,tpt in  template_dict.items():
        isValid = tpt.strip(BLANK_CHARS) != ""
        isValid = re.search(r"\[MAIN\]",tpt) is not None
        if not isValid:
            template_dict[lv] = DEFAULT_TEMPLATE
        template_dict[lv] = template_dict[lv].strip(BLANK_CHARS)
        indent = re.search(r"([ \t]*)\[MAIN\]", template_dict[lv])
        indent = indent.group(1) if indent else ""
        indent_dict[lv] = indent

    for i in range(len(chapter_list)):
        chapter_text = chapter_list[i]
        chapter_filename = filename_list[i]
        unique_id = unique_id_list[i]

        tag,title = title_tags[i]
        lv = int(tag[1]) if tag != "" else 0
        if lv in mainform.activated_tpt:
            xhtml_template = template_dict[lv]
            indent = indent_dict[lv]
        else:
            xhtml_template = template_dict[0]
            indent = indent_dict[0]

        xhtml = re.sub(r"\[TITLE\]",title,xhtml_template)
        xhtml = re.sub(r"[ \t]*\[MAIN\]",set_p_em(chapter_text,indent),xhtml,1)
        mime = 'application/xhtml+xml'

        bk.addfile(unique_id, chapter_filename, xhtml,mime)
        bk_spine.append((unique_id,None,None))

    bk.setspine_epub3(bk_spine)

def set_p_em(text,indent = ""):
    text = text.strip(BLANK_CHARS).replace("\\","\\\\")
    formatted_text = ''
    para = re.split('\r\n|\n',text)
    for p in para:
        p = p.strip(BLANK_CHARS)
        if p and p[0] != '<':
            if p:
                formatted_text += indent + '<p>' + p + '</p>\n'
        elif p and p[0] == '<':
            formatted_text += indent + p + '\n'
        else:
            formatted_text += indent + '<p><br/></p>\n'
    if formatted_text:
        return formatted_text[0:-1]
    else:
        return ""

def write_ini_file(mainform):
    conf = ModConfigParser()
    conf.add_section("ini_info")
    conf.set("ini_info", "ini_path", mainform.ini_openpath)
    conf.set("ini_info", "highlight_len", mainform.highlight_len)
    conf.set("ini_info","namebox_cur_text", mainform.namebox_cur_text)
    regexp_lv_conf = ",".join([str(lv) for lv,regexp in mainform.preset_regexp])
    conf.set('ini_info', 'regexp_lv', regexp_lv_conf)
    activated_tpt = ",".join([str(i) for i in mainform.activated_tpt])
    conf.set('ini_info', 'activated_tpt', activated_tpt)
    conf.add_section("regexp")
    if mainform.preset_regexp:
        order = 0
        for lv,regexp in mainform.preset_regexp:
            order += 1
            conf.set("regexp",'exp_%d'%order, regexp)

    conf.add_section("name_rules")
    if mainform.name_rules:
        order = 0
        for rule in mainform.name_rules:
            order += 1
            conf.set("name_rules",'rule_%d'%order, rule)

    with open('config.ini','w',encoding='utf-8') as cf:
        conf.write(cf)

def run(book):

    os.chdir(os.path.dirname(os.path.abspath(__file__)))

    global bk
    bk = book
    app = QtWidgets.QApplication(sys.argv)
    spliter = MainForm()
    spliter.show()
    app.exec()
    
    write_ini_file(spliter)

    if spliter.ready:
        build_xhtml(spliter)

    return 0

if __name__ == "__main__":
    from sigil_env import Ebook
    bk = Ebook('test.epub')
    run(bk)
    #bk.save_as("test_repack.epub")
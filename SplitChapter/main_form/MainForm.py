from pyqt_import import QtCore, QtGui, QtWidgets,Slot, SIGIL_QT_MAJOR_VERSION
from pyqt_import import main_ui
from main_form.TitleTree import TitleTree
from main_form.EditRegExp import EditRegExp
from main_form.TemplateBox import TemplateBox
from misc.ModConfigParser import ModConfigParser
from misc.default_config import DEFAULT_REGEXPS,DEFAULT_NAMERULES,BLANK_CHARS
from platform import system
import os,re,time,subprocess
from threading import Thread
from html import unescape



class MainForm(QtWidgets.QMainWindow):
    def __init__(self):
        super(MainForm, self).__init__()
        self.main_text = ""
        self.ui = ui = main_ui.Ui_MainWindow()
        ui.setupUi(self)
        self.init_function()
        self.load_ini()
        self.init_ui()
        self.ready = False

    def init_function(self):
        self.ui.template_btn.clicked.connect(self.template_setting)
        self.ui.open_btn.clicked.connect(self.open_filedialog)
        self.ui.add_rule_box_tool.clicked.connect(self.add_rule_box)
        self.ui.dec_rule_box_tool.clicked.connect(self.dec_rule_box)
        self.ui.edit_preset_regexp_tool.clicked.connect(self.edit_preset_regexp)
        self.ui.comfirm.clicked.connect(self.comfirmed)
        self.ui.preview_btn.clicked.connect(self.preview)
        self.ui.analysis_btn.clicked.connect(self.auto_analysis)
        self.ui.readme_lbl.clicked.connect(self.readme)

    def load_ini(self):

        conf = ModConfigParser()
        cfgpath = 'config.ini'

        if os.path.exists(cfgpath):
            conf.read(cfgpath, encoding="utf-8")
            try:
                self.ini_openpath = conf.get('ini_info', 'ini_path')
                self.highlight_len = conf.get('ini_info', 'highlight_len')
                self.namebox_cur_text= conf.get('ini_info', 'namebox_cur_text')
                activated_tpt = conf.get('ini_info', 'activated_tpt')
                if activated_tpt != "":
                    self.activated_tpt = [int(i) for i in activated_tpt.split(',')]
                else:
                    self.activated_tpt = []
                regexp_lv = conf.get("ini_info", "regexp_lv")
                regexp_lv = [int(lv) for lv in regexp_lv.split(",")]
                regexp_list = []
                regexp_items = conf.items('regexp')
                if regexp_items:
                    for op, regexp in regexp_items:
                        regexp_list.append(regexp)
                self.preset_regexp = list(zip(regexp_lv,regexp_list))
                self.name_rules = []
                namerules_items = conf.items('name_rules')
                if namerules_items:
                    for op, rule in namerules_items:
                        self.name_rules.append(rule)
            except Exception as e:
                print("error: %s"%e)
                self.default_ini()
        else:
            self.default_ini()

    def default_ini(self):
        self.ini_openpath = os.path.expanduser('~')
        self.preset_regexp = DEFAULT_REGEXPS
        self.name_rules = DEFAULT_NAMERULES
        self.highlight_len = '30'
        self.namebox_cur_text = DEFAULT_NAMERULES[-1]
        self.activated_tpt = []

    def init_ui(self):
        self.resize(740,self.height())
        self.centralwidget = self.centralWidget()
        self.path_input_line = self.ui.path_input_line
        self.gridLayout = self.findChild(QtWidgets.QGridLayout)
        self.ruleBox_widget = {
            'lev_1': self.findChild(QtWidgets.QSpinBox, 'lev_1'),
            'l1_regexp': self.findChild(QtWidgets.QComboBox, 'l1_regexp'),
            'l1_split': self.findChild(QtWidgets.QCheckBox, 'l1_split')
        }
        for lv, exp in self.preset_regexp:
            self.ruleBox_widget['l1_regexp'].addItem(exp)
        self.ruleBox_widget['l1_regexp'].setCurrentText('')
        self.ruleBox_widget['l1_regexp'].lineEdit().setClearButtonEnabled(True)
        self.ruleBox_count = 1  # 正则框的数量（包括空框）
        self.ignore_title = {'regexp': {}, 'ignore_position': []}  # 'regexp'键储存上一次匹配正则，'ignore_position'键储存待忽略标题位置。
        self.current_height = self.sizeHint().height()  # 因为调用sizeHint().height()的高度未必能及时反馈，所以用current_height来计算高度。
        self.inc_height = None
        self.setFixedHeight(self.current_height)

        self.ui.filename_rule_cbbox.setup_items(self.name_rules, self.namebox_cur_text)
    def open_filedialog(self, drop_path=None):
        if not drop_path:
            if SIGIL_QT_MAJOR_VERSION == 6:
                args = {"parent": self, "dir": self.ini_openpath, "filter": "*.txt"}
            elif SIGIL_QT_MAJOR_VERSION == 5:
                args = {"parent": self, "directory": self.ini_openpath, "filter": "*.txt"}
            file = QtWidgets.QFileDialog.getOpenFileName(**args)
            if not file[0]:
                return
            txt_path = file[0]
        else:
            txt_path = drop_path
        self.ini_openpath = os.path.dirname(txt_path)
        path_input_line = self.findChild(QtWidgets.QLineEdit, 'path_input_line')
        path_input_line.setText(txt_path)
        txt_process = Thread(target=self.read_text_threading, args=(txt_path,))
        txt_process.start()

    def comfirmed(self):
        ready = self.update_settings()
        if not ready:
            QtWidgets.QMessageBox.information(self, '警告', '文件命名规则语法错误！')
            return

        ready = self.txt_path and not self.txt_path.startswith('可')
        if not ready:
            QtWidgets.QMessageBox.information(self, '警告', '文件路径不能为空，请输入文件路径！')
            return

        self.ready = True
        QtCore.QCoreApplication.instance().quit()

    def template_setting(self):
        self.template_box = TemplateBox(activated_tpt = self.activated_tpt)
        self.template_box.template_activated_sig.connect(self.update_activated_templates)
        self.template_box.show()

    @Slot(list)
    def update_activated_templates(self,activated_tpt:list[int]):
        self.activated_tpt = activated_tpt


    def update_settings(self) -> bool:
        settings = {}
        settings['lev'], settings['regexp'], settings['split'] = {}, {}, {}
        for i in range(1, self.ruleBox_count + 1):
            settings['lev']['lev_%d' % i] = self.ruleBox_widget['lev_%d' % i].value()  # int
            settings['regexp']['l%d_regexp' % i] = self.ruleBox_widget['l%d_regexp' % i].currentText()  # str
            settings['split']['l%d_split' % i] = self.ruleBox_widget['l%d_split' % i].isChecked()  # bool

        self.regexp_settings = settings
        self.namebox_cur_text = self.ui.filename_rule_cbbox.currentText()
        self.name_rules = self.ui.filename_rule_cbbox.get_allItemText()
        self.txt_path = self.path_input_line.text()

        ready = self.ui.filename_rule_cbbox.parse_name_rule()

        if ready:
            self.name_rule_dict = {}
            self.name_rule_dict["lv_to_rule"] = self.ui.filename_rule_cbbox.lv_to_rule
            self.name_rule_dict["rule_to_preproc"] = self.ui.filename_rule_cbbox.rule_to_preproc
            self.name_rule_dict["rule_to_txtfragment"] = self.ui.filename_rule_cbbox.rule_to_txtfragment
        return ready


    def preview(self):
        self.update_settings()
        if self.txt_path == '' or self.txt_path.startswith('可'):
            QtWidgets.QMessageBox.information(self, '警告', '文件路径不能为空，请输入文件路径！')
            return
        else:
            if self.ignore_title['regexp'] != self.regexp_settings['regexp']:
                self.ignore_title['ignore_position'].clear()
            titles = self.split_text( preview=True)
            self.view = TitleTree(self, titles)
            self.view.show()
            self.ignore_title['regexp'] = self.regexp_settings['regexp'].copy()

    def readme(self):
        template_path = 'docs/readme.txt'
        template_path = os.path.abspath(template_path)
        startfile(template_path)

    def add_rule_box(self):

        if self.ruleBox_count >= 15:
            return
        self.ruleBox_count += 1
        order = self.ruleBox_count
        lev_box = QtWidgets.QSpinBox(self.centralwidget)
        lev_box.setStyleSheet("background-color:rgba(255, 255, 255, 0);")
        lev_box.setFrame(False)
        lev_box.setAlignment(QtCore.Qt.AlignRight | QtCore.Qt.AlignTrailing | QtCore.Qt.AlignVCenter)
        lev_box.setSuffix("级标题")
        lev_box.setMinimum(1)
        lev_box.setMaximum(6)
        lev_box.setProperty("value", 2)
        lev_box.setObjectName("lev_%d" % order)
        self.gridLayout.addWidget(lev_box, order, 0, 1, 1)
        self.ruleBox_widget["lev_%d" % order] = lev_box

        regexp = QtWidgets.QComboBox(self.centralwidget)
        regexp.setEnabled(True)
        font = QtGui.QFont("SimSun", 9, 50)
        regexp.setFont(font)
        regexp.setAutoFillBackground(False)
        regexp.setEditable(True)
        regexp.setObjectName("l%d_regexp" % order)
        for lv, reg in self.preset_regexp:
            regexp.addItem(reg)
        regexp.setCurrentText("")
        regexp.lineEdit().setClearButtonEnabled(True)
        self.gridLayout.addWidget(regexp, order, 1, 1, 1)
        self.ruleBox_widget["l%d_regexp" % order] = regexp

        page_split = QtWidgets.QCheckBox(self.centralwidget)
        page_split.setChecked(True)
        page_split.setObjectName("l%d_split" % order)
        self.gridLayout.addWidget(page_split, order, 2, 1, 1, QtCore.Qt.AlignHCenter | QtCore.Qt.AlignVCenter)
        self.ruleBox_widget["l%d_split" % order] = page_split
        if self.inc_height is None:
            # 增加的高度 = 网格布局第二行单元格高度 + 布局单元格的垂直间距
            self.inc_height = self.gridLayout.cellRect(1, 1).height() + self.gridLayout.verticalSpacing()
        self.setFixedHeight(self.current_height + self.inc_height)
        self.current_height += self.inc_height

    def dec_rule_box(self):
        order = self.ruleBox_count
        if order < 2:
            return
        self.ruleBox_widget['lev_%d' % order].deleteLater()
        del self.ruleBox_widget['lev_%d' % order]
        self.ruleBox_widget['l%d_regexp' % order].deleteLater()
        del self.ruleBox_widget['l%d_regexp' % order]
        self.ruleBox_widget['l%d_split' % order].deleteLater()
        del self.ruleBox_widget['l%d_split' % order]
        self.setFixedHeight(self.current_height - self.inc_height)
        self.current_height -= self.inc_height
        self.ruleBox_count -= 1

    def edit_preset_regexp(self):
        self.editbox = EditRegExp(self)
        self.editbox.show()

    def auto_analysis(self):
        def try_regexp(regexp):
            while self.main_text == '':
                time.sleep(0.1)
            if re.search(regexp, self.main_text, re.MULTILINE):
                return True
            else:
                return False

        txt_path = self.path_input_line.text()
        if txt_path == '' or txt_path.startswith('可'):
            QtWidgets.QMessageBox.information(self, '警告', '文件路径不能为空，请输入文件路径！')
            return

        self.setCursor(QtCore.Qt.WaitCursor)  # 改变鼠标光标为等待
        available_regexp = []
        for lv, regexp in self.preset_regexp:
            if try_regexp(regexp):
                available_regexp.append((lv,regexp))
        if available_regexp:
            need_boxes_num = len(available_regexp) - self.ruleBox_count
            if need_boxes_num > 0:
                for i in range(need_boxes_num):
                    self.add_rule_box()
            elif need_boxes_num < 0:
                for i in range(abs(need_boxes_num)):
                    self.dec_rule_box()
            index = 0
            for lv, regexp in available_regexp:
                index += 1
                self.ruleBox_widget["l%d_regexp" % index].setCurrentText(regexp)
                lv = 2 if 0 >= lv or 6 < lv else lv
                self.ruleBox_widget["lev_%d" % index].setValue(lv)
        else:
            QtWidgets.QMessageBox.information(self, '警告', '未能匹配到任何标题！')
        self.setCursor(QtCore.Qt.ArrowCursor)  # 改变光标为正常

    def read_text_threading(self,txt_path):
        if not os.path.exists(txt_path):
            self.main_text = ''
            return

        try:
            with open(txt_path, 'r', encoding='utf-8') as txtfile:
                text = txtfile.read()
        except:
            try:
                with open(txt_path, 'r', encoding='utf-16') as txtfile:
                    text = txtfile.read()
            except:
                with open(txt_path, 'r', encoding='gbk', errors='ignore') as txtfile:
                    text = txtfile.read()

        # 空文件时TEXT加一个空白符，防止主线程因等待TEXT而卡死。
        if text == '':
            self.main_text = ' '
            return

        text = unescape(text)
        text = text.replace(r'&', '&amp;')
        text = text.replace('<', '&lt;')
        text = text.replace('>', '&gt;')
        self.main_text = text

    def split_text(self, preview=False):
        while self.main_text == '':
            time.sleep(0.1)
        text = self.main_text
        titles_caught = []
        title_tags = []
        settings = self.regexp_settings
        count = self.ruleBox_count

        def sub_lv(match, lv, order):
            title_ = match.group().strip(BLANK_CHARS)
            title = '<h%d>' % lv + title_ + '</h%d>' % lv
            if preview:
                return title
            split_char = '<✄>' if settings['split']['l%d_split' % order] else ''
            return split_char + title

        for order in range(1, count + 1):
            lv = settings['lev']['lev_%d' % order]
            regexp = settings['regexp']['l%d_regexp' % order]
            regexp = regexp.strip(" \t")
            if regexp != "":
                text = re.sub(regexp, lambda m: sub_lv(m, lv, order), text, flags=re.MULTILINE)

        if preview:
            titles_caught = re.findall(r'<h(\d)>(.*?)<', text)
            return titles_caught

        ignore_list = []
        if self.ignore_title['regexp'] == settings['regexp']:
            if self.ignore_title['ignore_position'] != []:
                ignore_list = self.ignore_title['ignore_position']

        sub_ignore_count = [-1]

        def sub_ignore(match):
            sub_ignore_count[0] += 1
            if sub_ignore_count[0] == ignore_list[0]:
                ignore_list.pop(0)
                return match.group(1)
            return match.group(0)

        if ignore_list:
            ignore_list.sort()
            match_count = ignore_list[-1] + 1
            text = re.sub(r'(?:<✄>)?<h\d>(.*?)</h\d>', sub_ignore, text, match_count)

        title_tags = re.findall(r'<✄><(h\d)>(.*)<', text)
        chapter_list = text.split('<✄>')
        if chapter_list[0].strip(BLANK_CHARS) == "":
            chapter_list.pop(0)  # 第一个分章没有内容
        else:
            title_tags.insert(0,("",""))  # 给第一个分章加标题位
        return title_tags,chapter_list

    def closeEvent(self, a0):
        self.update_settings()
def startfile(path):
    _platform = system()
    if _platform == "Darwin": # Mac OS
        subprocess.call(["open", path])
    elif _platform == "Linux":# Linux
        subprocess.call(["xdg-open", path])
    else:
        try:
            os.startfile(path) # windows
        except:
            # 不支持的平台
            pass

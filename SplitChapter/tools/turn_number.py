# -*- coding: utf-8 -*-

import re

# 中文数字转阿拉伯
# 支持写法：
# 写法一： 一万三千零一十一、壹萬〇伍佰
# 写法二： 两千四百二十、两萬
# 写法三： 二〇〇一、三五一〇、贰零贰零

CN_TO_ARAB_MAP = {'两':2,'百':100,'佰':100,'千':1000,'仟':1000,'万':10000,'萬':10000}
CN_NUM_SIM = '零一二三四五六七八九十'
CN_NUM_TRA = '〇壹贰叁肆伍陆柒捌玖拾'
for index in range(11):
    CN_TO_ARAB_MAP[CN_NUM_SIM[index]] = index
    CN_TO_ARAB_MAP[CN_NUM_TRA[index]] = index

def cn_turn_arab(cn_num):
    if not isinstance(cn_num,str) or cn_num == '':
        return ""

    if cn_num[0] in '０１２３４５６７８９':
        return int(cn_num)

    if len(cn_num) == 1 and cn_num in '一二三四五六七八九十壹贰叁肆伍陆柒捌玖拾〇零':
        arab_num = CN_TO_ARAB_MAP[cn_num]
        return int(arab_num)

    test = re.match(r'[一二两三四五六七八九十壹贰叁肆伍陆柒捌玖拾][一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟萬〇零]+$',cn_num)

    if test is None or len(test.group()) < len(cn_num):
        return cn_num
    
    if re.match(r'[一二三四五六七八九壹贰叁肆伍陆柒捌玖〇零]+$',cn_num):
        test_type = 2
    else:
        test_type = 1

    # 中文数字类型为“二〇〇一”、“一三四五”这类的简单写法
    if test_type == 2:
        arab_num = ''
        for num in cn_num:
            digit = CN_TO_ARAB_MAP[num]
            arab_num += str(digit)
        return int(arab_num)

    # 中文数字类型为“一千四百零三”这类正常写法
    arab_num = 0
    base_digit = 1
    rate = 1
    for index in range(len(cn_num)):
        num = cn_num[index]
        if num in '一二两三四五六七八九壹贰叁肆伍陆柒捌玖':
            base_digit = CN_TO_ARAB_MAP[num]
        elif num in '十百千万拾佰仟萬':
            rate = CN_TO_ARAB_MAP[num]
            arab_num += base_digit * rate
        elif num in '零〇':
            if cn_num[index-1] in '一二三四五六七八九壹贰叁肆伍陆柒捌玖':
                arab_num += base_digit * 10
    if cn_num[-1] in '一二三四五六七八九壹贰叁肆伍陆柒捌玖':
        arab_num += CN_TO_ARAB_MAP[cn_num[-1]]
    return int(arab_num)
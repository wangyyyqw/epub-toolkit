from pyqt_import import QtCore, QtGui, QtWidgets,Signal,Slot
import re

R_OFFSET = 20 # QComboBox Item 绘制时最右端的留白宽度

class ItemDelegate(QtWidgets.QStyledItemDelegate):
    def paint(self, painter: QtGui.QPainter, option: QtWidgets.QStyleOptionViewItem, index: QtCore.QModelIndex) -> None:
        
        rect = option.rect
        x,y,w,h = rect.x(),rect.y(),rect.width(),rect.height()
        option.rect.setWidth(w-R_OFFSET)
        option.font.setPointSize(9)
        option.font.setBold(False)
        super().paint(painter, option, index)

        painter.setPen(QtGui.QColor(250, 168, 168))
        flags = QtCore.Qt.AlignmentFlag.AlignVCenter|QtCore.Qt.AlignmentFlag.AlignHCenter
        font:QtGui.QFont = option.font
        font.setPointSize(10)
        font.setWeight(QtGui.QFont.Weight.Black)
        painter.setFont(font)
        painter.drawText(x+w-R_OFFSET,y,R_OFFSET,h,flags,"×")


class MyWidget(QtWidgets.QWidget):
    def __init__(self, parent) -> None:
        super().__init__(parent)

class ComboBoxListView(QtWidgets.QListView):

    delButtonEnabledChanged_signal = Signal(bool)

    def __init__(self, parent: QtWidgets.QWidget ) -> None:
        super().__init__(parent)
        self.setMouseTracking(True)
        self.delButtonEnabled = False

    def mouseMoveEvent(self, e: QtGui.QMouseEvent) -> None:
        if e.pos().x() >= self.rect().width()-R_OFFSET and self.delButtonEnabled == False:
            self.delButtonEnabled = True
            self.delButtonEnabledChanged_signal.emit(True)
            self.viewport().update()

        elif e.pos().x() <= self.rect().width()-R_OFFSET and self.delButtonEnabled == True:
            self.delButtonEnabled = False
            self.delButtonEnabledChanged_signal.emit(False)
            self.viewport().update()
        return super().mouseMoveEvent(e)
    
    def leaveEvent(self,e) -> None:
        if self.delButtonEnabled:
            self.delButtonEnabled = False
            self.delButtonEnabledChanged_signal.emit(False)
            self.viewport().update()
        return super().leaveEvent(e)

    def paintEvent(self, e: QtGui.QPaintEvent) -> None:
        super().paintEvent(e)
        if self.delButtonEnabled:
            rect = self.visualRect(self.currentIndex())
            y,h = rect.y(),rect.height()
            painter = QtGui.QPainter(self.viewport())
            painter.setPen(QtGui.QColor(255, 0, 0))
            font = QtGui.QFont()
            font.setPointSize(10)
            font.setWeight(QtGui.QFont.Weight.Black)
            painter.setFont(font)
            flags = QtCore.Qt.AlignmentFlag.AlignVCenter|QtCore.Qt.AlignmentFlag.AlignHCenter
            painter.drawText(self.rect().width()-R_OFFSET,y,R_OFFSET,h,flags,"×")

    def Parent(self) -> QtWidgets.QComboBox:
        return self.parent().parent()

class FilenameRuleComboBox(QtWidgets.QComboBox):
    def __init__(self, parent = None) -> None:
        super().__init__(parent)
        self.init_settings()
        self.init_func()
        self.delButtonEnabled = False
    def init_settings(self):
        self.setMaxCount(9)
        self.setView(ComboBoxListView(self))
        self.setEditable(True)
        self.setItemDelegate(ItemDelegate(self))
    def init_func(self):
        self.activated.connect(self.itemClickedAction)
        self.view().delButtonEnabledChanged_signal.connect(self.delButtonEnabledChanged)
    def setup_items(self,items:list[str],current_text=""):
        self.addItems(items)
        self.setCurrentText(current_text)

    def get_allItemText(self) -> list[str]:
        items = []
        for i in range(self.count()):
            items.append(self.itemText(i))
        return items

    def hidePopup(self) -> None:
        if self.view().delButtonEnabled == True:
            return
        super().hidePopup()
    def itemClickedAction(self):
        if self.delButtonEnabled:
            row = self.view().currentIndex().row()
            self.removeItem(row)

    def keyPressEvent(self, e):
        if e.key() == QtCore.Qt.Key.Key_Return or \
           e.key() == QtCore.Qt.Key.Key_Enter:
            if self.count() >= self.maxCount():
                QtWidgets.QMessageBox.information(self, '警告', '文件命名规则储存数量已达上限！')
                return
            if self.parse_name_rule() == False:
                QtWidgets.QMessageBox.information(self, '警告', '文件命名规则语法错误！')
                return
        super().keyPressEvent(e)

    @Slot(bool)
    def delButtonEnabledChanged(self,is_enabled:bool):
        self.delButtonEnabled = is_enabled
        if self.delButtonEnabled == True:
            self.lastCurrentText = self.currentText()
            self.setUpdatesEnabled(False)
        else:
            self.setCurrentText(self.lastCurrentText)
            self.setUpdatesEnabled(True)

    def parse_name_rule(self) -> bool:
        if self.currentText() == "":
            self.lv_to_rule = {"default":"Section{0000}"}
            self.rule_to_txtfragment = {"Section{0000}":["Section",""]}
            self.rule_to_preproc = {"Section{0000}":[4]}
            return True

        rule_dict = {}
        text = self.currentText()
        text = text.replace(" ","").replace("\t","")

        rules = text.split("|")

        parts = [] # [(lv,namerule)]
        for rule in rules:
            part = rule.split(":")
            if len(part) != 2:
                return False
            part_ = (part[0],part[1])
            parts.append(part_)

        lv_list = []
        name_list = []
        for head,tail in parts:
            if head == "":
                return False
            if tail == "":
                return False
            lv_list.append(head.split(","))
            name_list.append(tail)

        count = 0
        for lv_s in lv_list:
            name_rule = name_list[count]
            count += 1
            for lv in lv_s:
                if lv not in ["default","h1","h2","h3","h4","h5","h6"]:
                    return False
                rule_dict[lv] = name_rule

        for lv,name_rule in rule_dict.items():
            variables = re.findall(r"\{(.+?)\}",name_rule)
            if variables == []:
                return False
            is_order = False
            for var in variables:
                if var in ["h1","h2","h3","h4","h5","h6"]:
                    continue
                if re.match(r"^(0+|\$+)$",var):
                    is_order = True
            if not is_order:
                return False
            if var.startswith("h"): # 限制最后一个变量不能是引用
                return False

        if not rule_dict.get("default"):
            rule_dict["default"] = "Section{0000}"

        # 规则预处理
        # 即把命名规则拆分为普通字符串列表和变量列表
        # 例如 "{h1}-S{000}-Chapter{$$$}" 拆分成 ["","-S","-Chapter",""]和["h1","000","$$$"]
        # 正常情况下，普通字符串的列表长度永远比变量列表多1个长度，
        # 变量列表进一步处理，把全局序号变量转为长度值，局部序号变量转为长度值的负值，引用变量保持原值，
        # 例如上述变量列表转为 ["h1",3,-3]
        # 在后处理的时候，直接把变量列表的数值替换为对应序号，
        # 拼接字符串按 普列[i] + 变列[i] 组合成字符串，补上 普列[-1] 即可。
        rule_to_txtfragment = {}
        rule_to_preproc = {}
        for lv,name_rule in rule_dict.items():
            variables = re.findall(r"\{(.+?)\}",name_rule)
            text_fragments = re.split(r"\{.+?\}",name_rule)
            pre_proc = []
            for var in variables:
                if var[0] == "0":
                    pre_proc.append(len(var))
                elif var[0] == "$":
                    pre_proc.append(-len(var))
                else:
                    pre_proc.append(var)
            rule_to_txtfragment[name_rule] = text_fragments
            rule_to_preproc[name_rule] = pre_proc

        self.lv_to_rule = rule_dict
        self.rule_to_txtfragment = rule_to_txtfragment
        self.rule_to_preproc = rule_to_preproc
        return True





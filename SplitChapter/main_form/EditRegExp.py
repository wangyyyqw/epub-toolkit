
from pyqt_import import QtCore, QtGui, QtWidgets
from misc.default_config import DEFAULT_REGEXPS
from pyqt_import import edit_regexp

class EditRegExpItemDelegate(QtWidgets.QStyledItemDelegate):
    def setModelData(self, editor, model, index):
        super(EditRegExpItemDelegate, self).setModelData(editor, model, index)
        if index.column() == 0:
            data = model.data(index, QtCore.Qt.EditRole)
            if data not in ["1","2","3","4","5","6"]:
                model.setData(index, "2", QtCore.Qt.EditRole)
class EditRegExp(QtWidgets.QWidget):
    def __init__(self ,parent = None):
        self.parent_ = parent
        super(EditRegExp ,self).__init__(None)
        self.ui = edit_regexp.Ui_edit_regexp()
        self.ui.setupUi(self)
        self.tree = self.ui.exp_tree
        self.init_ui()
        self.init_regexp()

    def parent(self):
        return self.parent_

    def init_ui(self):
        tree = self.tree
        tree.setColumnCount(2)
        tree.setHeaderLabels(["级别","正则表达式"])
        tree.headerItem().setTextAlignment(0, QtCore.Qt.AlignCenter)
        tree.headerItem().setTextAlignment(1, QtCore.Qt.AlignLeft | QtCore.Qt.AlignVCenter)
        tree.setColumnWidth(0, 34)
        tree.setIndentation(0)
        tree.setItemDelegate(EditRegExpItemDelegate(tree))

    def init_regexp(self):
        tree = self.tree
        mainform = self.parent()
        for lv,regexp in mainform.preset_regexp:
            item = QtWidgets.QTreeWidgetItem(tree, [str(lv), regexp])
            item.setFlags(QtCore.Qt.ItemIsSelectable | QtCore.Qt.ItemIsEditable | QtCore.Qt.ItemIsEnabled)
            item.setTextAlignment(0, QtCore.Qt.AlignBottom | QtCore.Qt.AlignHCenter)
            item.setTextAlignment(1, QtCore.Qt.AlignBottom | QtCore.Qt.AlignLeft)
            tree.addTopLevelItem(item)

    def add_item(self):
        item = QtWidgets.QTreeWidgetItem(self.tree, ["2", '请在此输入正则表达式'])
        item.setFlags(QtCore.Qt.ItemIsSelectable | QtCore.Qt.ItemIsEditable | QtCore.Qt.ItemIsEnabled)
        item.setTextAlignment(0, QtCore.Qt.AlignBottom | QtCore.Qt.AlignHCenter)
        item.setTextAlignment(1, QtCore.Qt.AlignBottom | QtCore.Qt.AlignLeft)
        self.tree.addTopLevelItem(item)

    def dec_item(self):
        row = self.tree.currentIndex().row()
        self.tree.takeTopLevelItem(row)

    def move_up_item(self):
        cur_row = self.tree.currentIndex().row()
        if cur_row == 0:
            return
        item = self.tree.takeTopLevelItem(cur_row)
        self.tree.insertTopLevelItem(cur_row-1, item)
        self.tree.setCurrentItem(item)

    def move_down_item(self):
        cur_row = self.tree.currentIndex().row()
        if cur_row == self.tree.topLevelItemCount() -1:
            return
        item = self.tree.takeTopLevelItem(cur_row)
        self.tree.insertTopLevelItem(cur_row+1, item)
        self.tree.setCurrentItem(item)

    def closeEvent(self, event):
        mainform = self.parent()
        regexps = []
        for index in range(self.tree.topLevelItemCount()):
            item = self.tree.topLevelItem(index)
            lv = int(item.text(0))
            regexp = item.text(1)
            regexps.append((lv, regexp))
        # 更新主窗口的预置正则
        if regexps == []:
            mainform.preset_regexp = DEFAULT_REGEXPS
        else:
            mainform.preset_regexp = regexps
        # 更新编辑框的预置正则
        ruleBox = mainform.ruleBox_widget
        for i in range(1, mainform.ruleBox_count + 1):
            ruleBox['l%d_regexp' % i].clear()
            for lv, exp in mainform.preset_regexp:
                ruleBox['l%d_regexp' % i].addItem(exp)
            ruleBox['l%d_regexp' % i].setCurrentText('')

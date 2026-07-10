from pyqt_import import QtGui, QtWidgets
from pyqt_import import treeview
import re
class TitleTree(QtWidgets.QWidget):

    def __init__(self,parent ,titles = []):
        super(TitleTree,self).__init__()
        self.parent_ = parent
        self.ui = treeview.Ui_Form()
        self.ui.setupUi(self)
        self.tree = self.ui.title_tree
        self.verticalLayout = self.ui.verticalLayout
        self.limit_lineEdit = self.ui.limit_lineEdit
        self.limit_lineEdit.setValidator(QtGui.QIntValidator(0,9999))
        self.limit_lineEdit.setText(self.parent_.highlight_len)
        self.length_limit = int(self.parent_.highlight_len)
        # 编辑框按下Enter键时发送信号
        self.limit_lineEdit.returnPressed.connect(self.reflash_highlight)
        self.seqcheck_button = self.ui.seqCheckSwitch
        self.init_ui()
        self.init_function()
        self.build_tree(titles)

    def init_ui(self):
        self.tree.setStyleSheet('''
        QTreeWidget { 
            alternate-background-color: rgb(238, 255, 231);
        }
        QTreeView::item {
            border:0px solid rgba(0,0,0,0);
            padding:1px 0px;
        }
        QHeaderView:section {
            background-color: #666;
            color:white;
            font-weight:bold;
        }
        ''')

    def init_function(self):
        self.ui.seqCheckSwitch.clicked.connect(self.tree.seq_check)
        self.ui.ChapterLengthCheck_pbtn.clicked.connect(self.chapter_len_check)
        self.ui.ExpandAll_pbtn.clicked.connect(self.tree.expand_all)
        self.ui.FoldAll_pbtn.clicked.connect(self.tree.fold_all)

    def build_tree(self ,titles):
        self.tree.build_tree(titles)
        self.verticalLayout.addWidget(self.tree)

    def chapter_len_check(self):
        text = self.parent_.main_text
        self.parent_.update_settings()
        settings = self.parent_.regexp_settings
        count = self.parent_.ruleBox_count
        for order in range(1,count +1):
            regexp = settings['regexp']['l%d_regexp'%order]
            regexp = regexp.strip(" \t")
            if regexp != "":
                text = re.sub(regexp,"<✄>",text,flags=re.MULTILINE)
        segment_list = text.split("<✄>")
        segment_list.pop(0)
        length_list = []
        for segment in segment_list:
            segment = re.sub(r"\s","",segment)
            length_list.append(len(segment))

        if length_list != []:
            self.tree.drawChapterLengthBarChart(length_list)

    def reflash_highlight(self):
        self.limit_lineEdit.clearFocus()
        if self.length_limit == int(self.limit_lineEdit.text()):
            return
        self.length_limit = int(self.limit_lineEdit.text())
        self.parent().highlight_len = self.limit_lineEdit.text()
        self.tree.reflash_highlight(self.length_limit)

    def parent(self):
        return self.parent_
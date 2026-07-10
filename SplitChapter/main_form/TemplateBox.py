
from pyqt_import import QtGui, QtWidgets, Signal
from pyqt_import import template_box
from misc.default_config import DEFAULT_TEMPLATE
import os

class TemplateBox(QtWidgets.QWidget):
    template_activated_sig = Signal(list)
    def __init__(self, parent=None, activated_tpt:list[int]=[]):
        super().__init__(parent)

        self.modified_tab = {i:False for i in range(7)}
        self.ui = template_box.Ui_template_box()
        self.ui.setupUi(self)
        self.initUI()
        self.initActivatedTemplates(activated_tpt)
        self.initTemplate()
        self.init_func()

    def initUI(self):
        self.setWindowIcon(QtGui.QIcon(":/icon/edit.png"))
        self.resize(600,375)
        self.setMinimumHeight(375)
        for cbox in self.ui.template_check_group.findChildren(QtWidgets.QCheckBox):
            cbox.setSizePolicy(QtWidgets.QSizePolicy.Fixed,QtWidgets.QSizePolicy.Minimum)
            cbox.setText(cbox.text()+"\u2002"*2)
        self.ui.template_check_group.setStyleSheet('''
        QGroupBox {
            font-size:14px;
            color:#333;
            border:1px solid yellowgreen;
            margin-top:8px;
            padding-top:7px;
            padding-bottom:2px;
        }
        QGroupBox::title {
            subcontrol-origin: margin;
            subcontrol-position: top center;
            padding-left:5px;
            padding-right:5px;
        }
        QCheckBox { 
            color:white;
            font-size:14px;
            padding:3px 0px;
            background-color: #8a8c8e;
            border-radius:5px;
            spacing:0px;
        }
        QCheckBox::hover {
            background-color:#FAC5CF;
            
        }
        QCheckBox::checked {
            background-color:#ED1941;
            font-weight:bold;
        }
        QCheckBox::indicator {
            width:14px;
            background-color:rgba(0,0,0,0);
        }
        ''')

        self.ui.template_tab.setCurrentIndex(0)
        self.ui.template_tab.setStyleSheet('''
        QTabBar::tab {
            font-size:13px;
            padding:0px 12px;
            height:20px;
            background-color:#eee;
            border:1px solid yellowgreen;
            border-top-left-radius:3px;
            border-top-right-radius:3px;
            font-weight:bold;
        }
        QTabBar::tab:selected {
            background-color:yellowgreen;
            border-top-left-radius:4px;
            border-top-right-radius:4px;
            padding:2px 10px;
        }
        QTabBar::tab:!selected {
            color:#777;
            margin-top:4px;
        }
        QTabBar::tab:!selected:hover {
            background-color:rgb(219, 236, 186);
        }
        ''')

    def initActivatedTemplates(self,activated_tpt:list[int]):
        for i in activated_tpt:
            cbox = self.ui.template_check_group.findChild(QtWidgets.QCheckBox,f"tpt_{i}_cbox")
            cbox.setChecked(True)

    def initTemplate(self):
        for i in range(self.ui.template_tab.count()):
            template_file = f"template/template_{i}.txt"
            if os.path.exists(template_file):
                with open(template_file, 'r', encoding="utf-8") as f:
                    template_text = f.read()
            else:
                template_text = DEFAULT_TEMPLATE
                self.modified_tab[i] = True
            text_editor = self.ui.template_tab.findChild(QtWidgets.QPlainTextEdit, f"text_edit_{i}")
            text_editor.insertPlainText(template_text)

    def init_func(self):
        for editor in self.ui.template_tab.findChildren(QtWidgets.QPlainTextEdit):
            editor.textChanged.connect(self.textChangedProcess)

    def textChangedProcess(self):
        i = self.ui.template_tab.currentIndex()
        self.modified_tab[i] = True

    def get_activated_templates(self) -> list[int]:
        activated_indexes = []
        for i in range(1,7):
            cbox = self.ui.template_check_group.findChild(QtWidgets.QCheckBox,f"tpt_{i}_cbox")
            if cbox.isChecked():
                activated_indexes.append(i)
        activated_indexes.sort()
        return activated_indexes

    def closeEvent(self, a0: QtGui.QCloseEvent) -> None:
        self.template_activated_sig.emit(self.get_activated_templates())
        for i,isModified in self.modified_tab.items():
            if not isModified:
                continue
            template_file = f"template/template_{i}.txt"
            tab_objname = f"text_edit_{i}"
            text_editor = self.ui.template_tab.findChild(QtWidgets.QPlainTextEdit, tab_objname)
            text = text_editor.toPlainText()
            with open(template_file, "w", encoding="utf-8") as f:
                f.write(text)
        return super().closeEvent(a0)

    

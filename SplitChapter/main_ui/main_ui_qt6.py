# -*- coding: utf-8 -*-

################################################################################
## Form generated from reading UI file 'main_ui.ui'
##
## Created by: Qt User Interface Compiler version 6.5.2
##
## WARNING! All changes made in this file will be lost when recompiling UI file!
################################################################################

from PySide6.QtCore import (QCoreApplication, QDate, QDateTime, QLocale,
    QMetaObject, QObject, QPoint, QRect,
    QSize, QTime, QUrl, Qt)
from PySide6.QtGui import (QBrush, QColor, QConicalGradient, QCursor,
    QFont, QFontDatabase, QGradient, QIcon,
    QImage, QKeySequence, QLinearGradient, QPainter,
    QPalette, QPixmap, QRadialGradient, QTransform)
from PySide6.QtWidgets import (QApplication, QCheckBox, QComboBox, QGridLayout,
    QHBoxLayout, QLabel, QLayout, QMainWindow,
    QPushButton, QSizePolicy, QSpinBox, QToolButton,
    QVBoxLayout, QWidget)

from widget_class.FilenameRuleComboBox import FilenameRuleComboBox
from widget_class.ImporterLineEdit import ImporterLineEdit
import res_rc

class Ui_MainWindow(object):
    def setupUi(self, MainWindow):
        if not MainWindow.objectName():
            MainWindow.setObjectName(u"MainWindow")
        MainWindow.setWindowModality(Qt.WindowModal)
        MainWindow.resize(689, 206)
        font = QFont()
        font.setFamilies([u"\u5b8b\u4f53"])
        font.setPointSize(11)
        font.setBold(True)
        MainWindow.setFont(font)
        icon = QIcon()
        icon.addFile(u":/icon/plugin.png", QSize(), QIcon.Normal, QIcon.Off)
        MainWindow.setWindowIcon(icon)
        self.centralwidget = QWidget(MainWindow)
        self.centralwidget.setObjectName(u"centralwidget")
        self.verticalLayout = QVBoxLayout(self.centralwidget)
        self.verticalLayout.setSpacing(3)
        self.verticalLayout.setObjectName(u"verticalLayout")
        self.verticalLayout.setSizeConstraint(QLayout.SetDefaultConstraint)
        self.horizontalLayout = QHBoxLayout()
        self.horizontalLayout.setObjectName(u"horizontalLayout")
        self.label = QLabel(self.centralwidget)
        self.label.setObjectName(u"label")

        self.horizontalLayout.addWidget(self.label)

        self.path_input_line = ImporterLineEdit(self.centralwidget)
        self.path_input_line.setObjectName(u"path_input_line")
        self.path_input_line.setEnabled(True)
        font1 = QFont()
        font1.setFamilies([u"Microsoft YaHei UI"])
        font1.setPointSize(10)
        font1.setBold(False)
        self.path_input_line.setFont(font1)
        self.path_input_line.setStyleSheet(u"color:#666666;border:1 solid #777777;background-color:rgb(255, 255, 127);padding-left:3;")
        self.path_input_line.setDragEnabled(True)
        self.path_input_line.setReadOnly(True)

        self.horizontalLayout.addWidget(self.path_input_line)

        self.open_btn = QPushButton(self.centralwidget)
        self.open_btn.setObjectName(u"open_btn")

        self.horizontalLayout.addWidget(self.open_btn)


        self.verticalLayout.addLayout(self.horizontalLayout)

        self.gridLayout = QGridLayout()
        self.gridLayout.setObjectName(u"gridLayout")
        self.gridLayout.setSizeConstraint(QLayout.SetMinimumSize)
        self.gridLayout.setHorizontalSpacing(5)
        self.gridLayout.setVerticalSpacing(6)
        self.gridLayout.setContentsMargins(5, 5, 15, -1)
        self.label_10 = QLabel(self.centralwidget)
        self.label_10.setObjectName(u"label_10")

        self.gridLayout.addWidget(self.label_10, 0, 2, 1, 1, Qt.AlignHCenter)

        self.l1_split = QCheckBox(self.centralwidget)
        self.l1_split.setObjectName(u"l1_split")
        self.l1_split.setText(u"")
        self.l1_split.setChecked(True)

        self.gridLayout.addWidget(self.l1_split, 1, 2, 1, 1, Qt.AlignHCenter|Qt.AlignVCenter)

        self.l1_regexp = QComboBox(self.centralwidget)
        self.l1_regexp.setObjectName(u"l1_regexp")
        self.l1_regexp.setEnabled(True)
        font2 = QFont()
        font2.setFamilies([u"\u5b8b\u4f53"])
        font2.setPointSize(9)
        font2.setBold(False)
        self.l1_regexp.setFont(font2)
        self.l1_regexp.setAutoFillBackground(False)
        self.l1_regexp.setEditable(True)
        self.l1_regexp.setCurrentText(u"")

        self.gridLayout.addWidget(self.l1_regexp, 1, 1, 1, 1)

        self.lev_1 = QSpinBox(self.centralwidget)
        self.lev_1.setObjectName(u"lev_1")
        self.lev_1.setStyleSheet(u"background-color:rgba(255, 255, 255, 0);")
        self.lev_1.setFrame(False)
        self.lev_1.setAlignment(Qt.AlignRight|Qt.AlignTrailing|Qt.AlignVCenter)
        self.lev_1.setReadOnly(False)
        self.lev_1.setSpecialValueText(u"")
        self.lev_1.setKeyboardTracking(False)
        self.lev_1.setSuffix(u"\u7ea7\u6807\u9898")
        self.lev_1.setMinimum(1)
        self.lev_1.setMaximum(6)
        self.lev_1.setValue(2)

        self.gridLayout.addWidget(self.lev_1, 1, 0, 1, 1)

        self.horizontalLayout_3 = QHBoxLayout()
        self.horizontalLayout_3.setSpacing(2)
        self.horizontalLayout_3.setObjectName(u"horizontalLayout_3")
        self.horizontalLayout_3.setContentsMargins(-1, -1, -1, 3)
        self.label_2 = QLabel(self.centralwidget)
        self.label_2.setObjectName(u"label_2")
#if QT_CONFIG(tooltip)
        self.label_2.setToolTip(u"")
#endif // QT_CONFIG(tooltip)

        self.horizontalLayout_3.addWidget(self.label_2)

        self.add_rule_box_tool = QToolButton(self.centralwidget)
        self.add_rule_box_tool.setObjectName(u"add_rule_box_tool")
#if QT_CONFIG(tooltip)
        self.add_rule_box_tool.setToolTip(u"\u6dfb\u52a0\u6b63\u5219\u6846")
#endif // QT_CONFIG(tooltip)
        icon1 = QIcon()
        icon1.addFile(u":/icon/plus.png", QSize(), QIcon.Normal, QIcon.Off)
        self.add_rule_box_tool.setIcon(icon1)

        self.horizontalLayout_3.addWidget(self.add_rule_box_tool)

        self.dec_rule_box_tool = QToolButton(self.centralwidget)
        self.dec_rule_box_tool.setObjectName(u"dec_rule_box_tool")
#if QT_CONFIG(tooltip)
        self.dec_rule_box_tool.setToolTip(u"\u51cf\u5c11\u6b63\u5219\u6846")
#endif // QT_CONFIG(tooltip)
        icon2 = QIcon()
        icon2.addFile(u":/icon/delete.png", QSize(), QIcon.Normal, QIcon.Off)
        self.dec_rule_box_tool.setIcon(icon2)

        self.horizontalLayout_3.addWidget(self.dec_rule_box_tool)

        self.edit_preset_regexp_tool = QToolButton(self.centralwidget)
        self.edit_preset_regexp_tool.setObjectName(u"edit_preset_regexp_tool")
#if QT_CONFIG(tooltip)
        self.edit_preset_regexp_tool.setToolTip(u"\u7f16\u8f91\u9884\u7f6e\u6b63\u5219")
#endif // QT_CONFIG(tooltip)
        icon3 = QIcon()
        icon3.addFile(u":/icon/edit.png", QSize(), QIcon.Normal, QIcon.Off)
        self.edit_preset_regexp_tool.setIcon(icon3)

        self.horizontalLayout_3.addWidget(self.edit_preset_regexp_tool)

        self.horizontalLayout_3.setStretch(0, 1)

        self.gridLayout.addLayout(self.horizontalLayout_3, 0, 1, 1, 1)

        self.gridLayout.setRowStretch(0, 2)

        self.verticalLayout.addLayout(self.gridLayout)

        self.horizontalLayout_4 = QHBoxLayout()
        self.horizontalLayout_4.setObjectName(u"horizontalLayout_4")
        self.horizontalLayout_4.setContentsMargins(0, 0, -1, -1)
        self.readme_lbl = QPushButton(self.centralwidget)
        self.readme_lbl.setObjectName(u"readme_lbl")
        font3 = QFont()
        font3.setFamilies([u"\u9ed1\u4f53"])
        font3.setPointSize(11)
        font3.setBold(False)
        font3.setItalic(True)
        self.readme_lbl.setFont(font3)
        self.readme_lbl.setCursor(QCursor(Qt.PointingHandCursor))
        self.readme_lbl.setStyleSheet(u"color:rgb(255, 0, 0);background-color:rgba(255, 255, 255,0)")

        self.horizontalLayout_4.addWidget(self.readme_lbl, 0, Qt.AlignLeft)


        self.verticalLayout.addLayout(self.horizontalLayout_4)

        self.horizontalLayout_2 = QHBoxLayout()
        self.horizontalLayout_2.setSpacing(4)
        self.horizontalLayout_2.setObjectName(u"horizontalLayout_2")
        self.template_btn = QPushButton(self.centralwidget)
        self.template_btn.setObjectName(u"template_btn")
        self.template_btn.setMinimumSize(QSize(80, 0))

        self.horizontalLayout_2.addWidget(self.template_btn)

        self.label_3 = QLabel(self.centralwidget)
        self.label_3.setObjectName(u"label_3")
        font4 = QFont()
        font4.setFamilies([u"\u5b8b\u4f53"])
        font4.setPointSize(10)
        font4.setBold(True)
        self.label_3.setFont(font4)

        self.horizontalLayout_2.addWidget(self.label_3)

        self.filename_rule_cbbox = FilenameRuleComboBox(self.centralwidget)
        self.filename_rule_cbbox.setObjectName(u"filename_rule_cbbox")
        sizePolicy = QSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)
        sizePolicy.setHorizontalStretch(0)
        sizePolicy.setVerticalStretch(0)
        sizePolicy.setHeightForWidth(self.filename_rule_cbbox.sizePolicy().hasHeightForWidth())
        self.filename_rule_cbbox.setSizePolicy(sizePolicy)
        self.filename_rule_cbbox.setMinimumSize(QSize(120, 0))
        self.filename_rule_cbbox.setFont(font2)

        self.horizontalLayout_2.addWidget(self.filename_rule_cbbox)

        self.comfirm = QPushButton(self.centralwidget)
        self.comfirm.setObjectName(u"comfirm")

        self.horizontalLayout_2.addWidget(self.comfirm)

        self.preview_btn = QPushButton(self.centralwidget)
        self.preview_btn.setObjectName(u"preview_btn")

        self.horizontalLayout_2.addWidget(self.preview_btn)

        self.analysis_btn = QPushButton(self.centralwidget)
        self.analysis_btn.setObjectName(u"analysis_btn")

        self.horizontalLayout_2.addWidget(self.analysis_btn)


        self.verticalLayout.addLayout(self.horizontalLayout_2)

        MainWindow.setCentralWidget(self.centralwidget)

        self.retranslateUi(MainWindow)

        QMetaObject.connectSlotsByName(MainWindow)
    # setupUi

    def retranslateUi(self, MainWindow):
        MainWindow.setWindowTitle(QCoreApplication.translate("MainWindow", u"\u5206\u7ae0\u52a9\u624b", None))
        self.label.setText(QCoreApplication.translate("MainWindow", u"\u5bfc\u5165TXT\u6587\u4ef6", None))
        self.path_input_line.setText(QCoreApplication.translate("MainWindow", u"\u53ef\u5c06TXT\u6587\u4ef6\u62d6\u66f3\u81f3\u6b64", None))
        self.open_btn.setText(QCoreApplication.translate("MainWindow", u"\u6253\u5f00", None))
        self.label_10.setText(QCoreApplication.translate("MainWindow", u" \u5206\u5272 ", None))
        self.label_2.setText(QCoreApplication.translate("MainWindow", u"\u6b63\u5219\u8868\u8fbe\u5f0f", None))
        self.add_rule_box_tool.setText("")
        self.dec_rule_box_tool.setText("")
        self.edit_preset_regexp_tool.setText("")
        self.readme_lbl.setText(QCoreApplication.translate("MainWindow", u"\u3000\u6ce8\uff1a\u70b9\u51fb\u8fd9\u91cc\u67e5\u770b\u4f7f\u7528\u8bf4\u660e\u3000", None))
        self.template_btn.setText(QCoreApplication.translate("MainWindow", u"\u6a21\u677f\u8bbe\u7f6e", None))
        self.label_3.setText(QCoreApplication.translate("MainWindow", u"\u547d\u540d\u89c4\u5219", None))
        self.comfirm.setText(QCoreApplication.translate("MainWindow", u"\u6267\u884c", None))
        self.preview_btn.setText(QCoreApplication.translate("MainWindow", u"\u9884\u89c8", None))
        self.analysis_btn.setText(QCoreApplication.translate("MainWindow", u"\u81ea\u52a8\u5206\u6790", None))
    # retranslateUi


# -*- coding: utf-8 -*-

################################################################################
## Form generated from reading UI file 'template_box.ui'
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
from PySide6.QtWidgets import (QApplication, QCheckBox, QGroupBox, QHBoxLayout,
    QSizePolicy, QTabWidget, QVBoxLayout, QWidget)

from widget_class.TemplateEdit import TemplateEdit

class Ui_template_box(object):
    def setupUi(self, template_box):
        if not template_box.objectName():
            template_box.setObjectName(u"template_box")
        template_box.resize(520, 345)
        self.verticalLayout = QVBoxLayout(template_box)
        self.verticalLayout.setObjectName(u"verticalLayout")
        self.template_check_group = QGroupBox(template_box)
        self.template_check_group.setObjectName(u"template_check_group")
        self.template_check_group.setAlignment(Qt.AlignCenter)
        self.horizontalLayout = QHBoxLayout(self.template_check_group)
        self.horizontalLayout.setObjectName(u"horizontalLayout")
        self.tpt_1_cbox = QCheckBox(self.template_check_group)
        self.tpt_1_cbox.setObjectName(u"tpt_1_cbox")

        self.horizontalLayout.addWidget(self.tpt_1_cbox)

        self.tpt_2_cbox = QCheckBox(self.template_check_group)
        self.tpt_2_cbox.setObjectName(u"tpt_2_cbox")

        self.horizontalLayout.addWidget(self.tpt_2_cbox)

        self.tpt_3_cbox = QCheckBox(self.template_check_group)
        self.tpt_3_cbox.setObjectName(u"tpt_3_cbox")

        self.horizontalLayout.addWidget(self.tpt_3_cbox)

        self.tpt_4_cbox = QCheckBox(self.template_check_group)
        self.tpt_4_cbox.setObjectName(u"tpt_4_cbox")

        self.horizontalLayout.addWidget(self.tpt_4_cbox)

        self.tpt_5_cbox = QCheckBox(self.template_check_group)
        self.tpt_5_cbox.setObjectName(u"tpt_5_cbox")

        self.horizontalLayout.addWidget(self.tpt_5_cbox)

        self.tpt_6_cbox = QCheckBox(self.template_check_group)
        self.tpt_6_cbox.setObjectName(u"tpt_6_cbox")

        self.horizontalLayout.addWidget(self.tpt_6_cbox)


        self.verticalLayout.addWidget(self.template_check_group)

        self.template_tab = QTabWidget(template_box)
        self.template_tab.setObjectName(u"template_tab")
        self.tpt_tab_0 = QWidget()
        self.tpt_tab_0.setObjectName(u"tpt_tab_0")
        self.verticalLayout_2 = QVBoxLayout(self.tpt_tab_0)
        self.verticalLayout_2.setObjectName(u"verticalLayout_2")
        self.verticalLayout_2.setContentsMargins(0, 0, 0, 0)
        self.text_edit_0 = TemplateEdit(self.tpt_tab_0)
        self.text_edit_0.setObjectName(u"text_edit_0")

        self.verticalLayout_2.addWidget(self.text_edit_0)

        self.template_tab.addTab(self.tpt_tab_0, "")
        self.tpt_tab_1 = QWidget()
        self.tpt_tab_1.setObjectName(u"tpt_tab_1")
        self.verticalLayout_3 = QVBoxLayout(self.tpt_tab_1)
        self.verticalLayout_3.setObjectName(u"verticalLayout_3")
        self.verticalLayout_3.setContentsMargins(0, 0, 0, 0)
        self.text_edit_1 = TemplateEdit(self.tpt_tab_1)
        self.text_edit_1.setObjectName(u"text_edit_1")

        self.verticalLayout_3.addWidget(self.text_edit_1)

        self.template_tab.addTab(self.tpt_tab_1, "")
        self.tpt_tab_2 = QWidget()
        self.tpt_tab_2.setObjectName(u"tpt_tab_2")
        self.verticalLayout_4 = QVBoxLayout(self.tpt_tab_2)
        self.verticalLayout_4.setObjectName(u"verticalLayout_4")
        self.verticalLayout_4.setContentsMargins(0, 0, 0, 0)
        self.text_edit_2 = TemplateEdit(self.tpt_tab_2)
        self.text_edit_2.setObjectName(u"text_edit_2")

        self.verticalLayout_4.addWidget(self.text_edit_2)

        self.template_tab.addTab(self.tpt_tab_2, "")
        self.tpt_tab_3 = QWidget()
        self.tpt_tab_3.setObjectName(u"tpt_tab_3")
        self.verticalLayout_5 = QVBoxLayout(self.tpt_tab_3)
        self.verticalLayout_5.setObjectName(u"verticalLayout_5")
        self.verticalLayout_5.setContentsMargins(0, 0, 0, 0)
        self.text_edit_3 = TemplateEdit(self.tpt_tab_3)
        self.text_edit_3.setObjectName(u"text_edit_3")

        self.verticalLayout_5.addWidget(self.text_edit_3)

        self.template_tab.addTab(self.tpt_tab_3, "")
        self.tpt_tab_4 = QWidget()
        self.tpt_tab_4.setObjectName(u"tpt_tab_4")
        self.verticalLayout_6 = QVBoxLayout(self.tpt_tab_4)
        self.verticalLayout_6.setObjectName(u"verticalLayout_6")
        self.verticalLayout_6.setContentsMargins(0, 0, 0, 0)
        self.text_edit_4 = TemplateEdit(self.tpt_tab_4)
        self.text_edit_4.setObjectName(u"text_edit_4")

        self.verticalLayout_6.addWidget(self.text_edit_4)

        self.template_tab.addTab(self.tpt_tab_4, "")
        self.tpt_tab_5 = QWidget()
        self.tpt_tab_5.setObjectName(u"tpt_tab_5")
        self.verticalLayout_7 = QVBoxLayout(self.tpt_tab_5)
        self.verticalLayout_7.setObjectName(u"verticalLayout_7")
        self.verticalLayout_7.setContentsMargins(0, 0, 0, 0)
        self.text_edit_5 = TemplateEdit(self.tpt_tab_5)
        self.text_edit_5.setObjectName(u"text_edit_5")

        self.verticalLayout_7.addWidget(self.text_edit_5)

        self.template_tab.addTab(self.tpt_tab_5, "")
        self.tpt_tab_6 = QWidget()
        self.tpt_tab_6.setObjectName(u"tpt_tab_6")
        self.verticalLayout_8 = QVBoxLayout(self.tpt_tab_6)
        self.verticalLayout_8.setObjectName(u"verticalLayout_8")
        self.verticalLayout_8.setContentsMargins(0, 0, 0, 0)
        self.text_edit_6 = TemplateEdit(self.tpt_tab_6)
        self.text_edit_6.setObjectName(u"text_edit_6")

        self.verticalLayout_8.addWidget(self.text_edit_6)

        self.template_tab.addTab(self.tpt_tab_6, "")

        self.verticalLayout.addWidget(self.template_tab)


        self.retranslateUi(template_box)

        self.template_tab.setCurrentIndex(6)


        QMetaObject.connectSlotsByName(template_box)
    # setupUi

    def retranslateUi(self, template_box):
        template_box.setWindowTitle(QCoreApplication.translate("template_box", u"\u6a21\u677f\u8bbe\u7f6e", None))
        self.template_check_group.setTitle(QCoreApplication.translate("template_box", u"\u6fc0\u6d3b\u6a21\u677f", None))
        self.tpt_1_cbox.setText(QCoreApplication.translate("template_box", u"1\u7ea7\u6a21\u677f", None))
        self.tpt_2_cbox.setText(QCoreApplication.translate("template_box", u"2\u7ea7\u6a21\u677f", None))
        self.tpt_3_cbox.setText(QCoreApplication.translate("template_box", u"3\u7ea7\u6a21\u677f", None))
        self.tpt_4_cbox.setText(QCoreApplication.translate("template_box", u"4\u7ea7\u6a21\u677f", None))
        self.tpt_5_cbox.setText(QCoreApplication.translate("template_box", u"5\u7ea7\u6a21\u677f", None))
        self.tpt_6_cbox.setText(QCoreApplication.translate("template_box", u"6\u7ea7\u6a21\u677f", None))
        self.template_tab.setTabText(self.template_tab.indexOf(self.tpt_tab_0), QCoreApplication.translate("template_box", u"\u9ed8\u8ba4\u6a21\u677f", None))
        self.template_tab.setTabText(self.template_tab.indexOf(self.tpt_tab_1), QCoreApplication.translate("template_box", u"1\u7ea7\u6a21\u677f", None))
        self.template_tab.setTabText(self.template_tab.indexOf(self.tpt_tab_2), QCoreApplication.translate("template_box", u"2\u7ea7\u6a21\u677f", None))
        self.template_tab.setTabText(self.template_tab.indexOf(self.tpt_tab_3), QCoreApplication.translate("template_box", u"3\u7ea7\u6a21\u677f", None))
        self.template_tab.setTabText(self.template_tab.indexOf(self.tpt_tab_4), QCoreApplication.translate("template_box", u"4\u7ea7\u6a21\u677f", None))
        self.template_tab.setTabText(self.template_tab.indexOf(self.tpt_tab_5), QCoreApplication.translate("template_box", u"5\u7ea7\u6a21\u677f", None))
        self.template_tab.setTabText(self.template_tab.indexOf(self.tpt_tab_6), QCoreApplication.translate("template_box", u"6\u7ea7\u6a21\u677f", None))
    # retranslateUi


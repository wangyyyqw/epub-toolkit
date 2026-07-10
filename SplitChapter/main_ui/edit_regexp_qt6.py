# -*- coding: utf-8 -*-

################################################################################
## Form generated from reading UI file 'edit_regexp.ui'
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
from PySide6.QtWidgets import (QApplication, QHBoxLayout, QHeaderView, QSizePolicy,
    QSpacerItem, QToolButton, QTreeWidget, QTreeWidgetItem,
    QVBoxLayout, QWidget)
import res_rc

class Ui_edit_regexp(object):
    def setupUi(self, edit_regexp):
        if not edit_regexp.objectName():
            edit_regexp.setObjectName(u"edit_regexp")
        edit_regexp.setWindowModality(Qt.ApplicationModal)
        edit_regexp.resize(423, 221)
        icon = QIcon()
        icon.addFile(u":/icon/edit.png", QSize(), QIcon.Normal, QIcon.Off)
        edit_regexp.setWindowIcon(icon)
        self.verticalLayout = QVBoxLayout(edit_regexp)
        self.verticalLayout.setObjectName(u"verticalLayout")
        self.verticalLayout.setContentsMargins(4, 4, 4, 4)
        self.exp_tree = QTreeWidget(edit_regexp)
        __qtreewidgetitem = QTreeWidgetItem()
        __qtreewidgetitem.setText(0, u"1");
        self.exp_tree.setHeaderItem(__qtreewidgetitem)
        self.exp_tree.setObjectName(u"exp_tree")
        self.exp_tree.setStyleSheet(u"alternate-background-color:rgb(235, 235, 235);")
        self.exp_tree.setAlternatingRowColors(True)

        self.verticalLayout.addWidget(self.exp_tree)

        self.horizontalLayout = QHBoxLayout()
        self.horizontalLayout.setObjectName(u"horizontalLayout")
        self.horizontalSpacer = QSpacerItem(40, 20, QSizePolicy.Expanding, QSizePolicy.Minimum)

        self.horizontalLayout.addItem(self.horizontalSpacer)

        self.toolButton_4 = QToolButton(edit_regexp)
        self.toolButton_4.setObjectName(u"toolButton_4")
        icon1 = QIcon()
        icon1.addFile(u":/icon/arrow-up.png", QSize(), QIcon.Normal, QIcon.Off)
        self.toolButton_4.setIcon(icon1)

        self.horizontalLayout.addWidget(self.toolButton_4)

        self.toolButton = QToolButton(edit_regexp)
        self.toolButton.setObjectName(u"toolButton")
        icon2 = QIcon()
        icon2.addFile(u":/icon/arrow-down.png", QSize(), QIcon.Normal, QIcon.Off)
        self.toolButton.setIcon(icon2)

        self.horizontalLayout.addWidget(self.toolButton)

        self.horizontalSpacer_2 = QSpacerItem(40, 20, QSizePolicy.Expanding, QSizePolicy.Minimum)

        self.horizontalLayout.addItem(self.horizontalSpacer_2)

        self.toolButton_2 = QToolButton(edit_regexp)
        self.toolButton_2.setObjectName(u"toolButton_2")
        icon3 = QIcon()
        icon3.addFile(u":/icon/plus.png", QSize(), QIcon.Normal, QIcon.Off)
        self.toolButton_2.setIcon(icon3)

        self.horizontalLayout.addWidget(self.toolButton_2)

        self.toolButton_3 = QToolButton(edit_regexp)
        self.toolButton_3.setObjectName(u"toolButton_3")
        icon4 = QIcon()
        icon4.addFile(u":/icon/delete.png", QSize(), QIcon.Normal, QIcon.Off)
        self.toolButton_3.setIcon(icon4)

        self.horizontalLayout.addWidget(self.toolButton_3)

        self.horizontalLayout.setStretch(0, 5)
        self.horizontalLayout.setStretch(3, 4)

        self.verticalLayout.addLayout(self.horizontalLayout)


        self.retranslateUi(edit_regexp)
        self.toolButton_4.clicked.connect(edit_regexp.move_up_item)
        self.toolButton.clicked.connect(edit_regexp.move_down_item)
        self.toolButton_2.clicked.connect(edit_regexp.add_item)
        self.toolButton_3.clicked.connect(edit_regexp.dec_item)

        QMetaObject.connectSlotsByName(edit_regexp)
    # setupUi

    def retranslateUi(self, edit_regexp):
        edit_regexp.setWindowTitle(QCoreApplication.translate("edit_regexp", u"\u7f16\u8f91\u9884\u7f6e\u6b63\u5219", None))
        self.toolButton_4.setText("")
        self.toolButton.setText("")
        self.toolButton_2.setText("")
        self.toolButton_3.setText("")
    # retranslateUi


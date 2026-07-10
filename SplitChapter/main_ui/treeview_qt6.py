# -*- coding: utf-8 -*-

################################################################################
## Form generated from reading UI file 'treeview.ui'
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
from PySide6.QtWidgets import (QAbstractItemView, QApplication, QHBoxLayout, QHeaderView,
    QLabel, QPushButton, QSizePolicy, QSpacerItem,
    QTreeWidgetItem, QVBoxLayout, QWidget)

from widget_class.LenLineEdit import LenLineEdit
from widget_class.PreviewTreeWidget import PreviewTreeWidget
import res_rc

class Ui_Form(object):
    def setupUi(self, Form):
        if not Form.objectName():
            Form.setObjectName(u"Form")
        Form.setWindowModality(Qt.ApplicationModal)
        Form.resize(303, 452)
        Form.setWindowTitle(u"\u6807\u9898\u9884\u89c8")
        icon = QIcon()
        icon.addFile(u":/icon/plugin.png", QSize(), QIcon.Normal, QIcon.Off)
        Form.setWindowIcon(icon)
        self.verticalLayout = QVBoxLayout(Form)
        self.verticalLayout.setSpacing(0)
        self.verticalLayout.setObjectName(u"verticalLayout")
        self.verticalLayout.setContentsMargins(4, 4, 4, 4)
        self.horizontalLayout_2 = QHBoxLayout()
        self.horizontalLayout_2.setSpacing(3)
        self.horizontalLayout_2.setObjectName(u"horizontalLayout_2")
        self.horizontalLayout_2.setContentsMargins(3, 5, 5, 5)
        self.label = QLabel(Form)
        self.label.setObjectName(u"label")
        self.label.setText(u"\u6807\u9898\u957f\u5ea6\u8d85")

        self.horizontalLayout_2.addWidget(self.label)

        self.limit_lineEdit = LenLineEdit(Form)
        self.limit_lineEdit.setObjectName(u"limit_lineEdit")
        sizePolicy = QSizePolicy(QSizePolicy.Minimum, QSizePolicy.Fixed)
        sizePolicy.setHorizontalStretch(0)
        sizePolicy.setVerticalStretch(0)
        sizePolicy.setHeightForWidth(self.limit_lineEdit.sizePolicy().hasHeightForWidth())
        self.limit_lineEdit.setSizePolicy(sizePolicy)
        self.limit_lineEdit.setMinimumSize(QSize(30, 18))
        self.limit_lineEdit.setMaximumSize(QSize(30, 18))
        self.limit_lineEdit.setInputMask(u"")
        self.limit_lineEdit.setText(u"")
        self.limit_lineEdit.setPlaceholderText(u"")

        self.horizontalLayout_2.addWidget(self.limit_lineEdit)

        self.label_2 = QLabel(Form)
        self.label_2.setObjectName(u"label_2")
        self.label_2.setText(u"\u663e\u9ad8\u4eae")

        self.horizontalLayout_2.addWidget(self.label_2)

        self.horizontalSpacer = QSpacerItem(40, 20, QSizePolicy.Expanding, QSizePolicy.Minimum)

        self.horizontalLayout_2.addItem(self.horizontalSpacer)

        self.ChapterLengthCheck_pbtn = QPushButton(Form)
        self.ChapterLengthCheck_pbtn.setObjectName(u"ChapterLengthCheck_pbtn")
        self.ChapterLengthCheck_pbtn.setMinimumSize(QSize(100, 0))
        self.ChapterLengthCheck_pbtn.setMaximumSize(QSize(100, 16777215))

        self.horizontalLayout_2.addWidget(self.ChapterLengthCheck_pbtn)

        self.horizontalLayout_2.setStretch(3, 1)

        self.verticalLayout.addLayout(self.horizontalLayout_2)

        self.horizontalLayout = QHBoxLayout()
        self.horizontalLayout.setSpacing(3)
        self.horizontalLayout.setObjectName(u"horizontalLayout")
        self.horizontalLayout.setContentsMargins(3, 0, 5, 5)
        self.label_3 = QLabel(Form)
        self.label_3.setObjectName(u"label_3")
        self.label_3.setText(u"\u65ad\u5e8f\u68c0\u67e5  ")

        self.horizontalLayout.addWidget(self.label_3)

        self.seqCheckSwitch = QPushButton(Form)
        self.seqCheckSwitch.setObjectName(u"seqCheckSwitch")
        self.seqCheckSwitch.setMinimumSize(QSize(50, 0))
        self.seqCheckSwitch.setMaximumSize(QSize(60, 16777215))
        self.seqCheckSwitch.setText(u"OFF")
        self.seqCheckSwitch.setCheckable(False)

        self.horizontalLayout.addWidget(self.seqCheckSwitch)

        self.horizontalSpacer_2 = QSpacerItem(40, 20, QSizePolicy.Expanding, QSizePolicy.Minimum)

        self.horizontalLayout.addItem(self.horizontalSpacer_2)

        self.FoldAll_pbtn = QPushButton(Form)
        self.FoldAll_pbtn.setObjectName(u"FoldAll_pbtn")
        self.FoldAll_pbtn.setMinimumSize(QSize(48, 0))
        self.FoldAll_pbtn.setMaximumSize(QSize(48, 16777215))

        self.horizontalLayout.addWidget(self.FoldAll_pbtn)

        self.ExpandAll_pbtn = QPushButton(Form)
        self.ExpandAll_pbtn.setObjectName(u"ExpandAll_pbtn")
        self.ExpandAll_pbtn.setMinimumSize(QSize(48, 0))
        self.ExpandAll_pbtn.setMaximumSize(QSize(48, 16777215))

        self.horizontalLayout.addWidget(self.ExpandAll_pbtn)


        self.verticalLayout.addLayout(self.horizontalLayout)

        self.title_tree = PreviewTreeWidget(Form)
        __qtreewidgetitem = QTreeWidgetItem()
        __qtreewidgetitem.setText(0, u"1");
        self.title_tree.setHeaderItem(__qtreewidgetitem)
        self.title_tree.setObjectName(u"title_tree")
        self.title_tree.setStyleSheet(u"")
        self.title_tree.setAlternatingRowColors(True)
        self.title_tree.setSelectionMode(QAbstractItemView.NoSelection)
        self.title_tree.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.title_tree.setIndentation(10)
        self.title_tree.setAnimated(False)
        self.title_tree.header().setVisible(False)

        self.verticalLayout.addWidget(self.title_tree)


        self.retranslateUi(Form)

        QMetaObject.connectSlotsByName(Form)
    # setupUi

    def retranslateUi(self, Form):
        self.ChapterLengthCheck_pbtn.setText(QCoreApplication.translate("Form", u" \u7ae0\u8282\u5b57\u6570\u68c0\u67e5 ", None))
        self.FoldAll_pbtn.setText(QCoreApplication.translate("Form", u"\u6298\u53e0", None))
        self.ExpandAll_pbtn.setText(QCoreApplication.translate("Form", u"\u5c55\u5f00", None))
        pass
    # retranslateUi


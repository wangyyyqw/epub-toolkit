

from pyqt_import import QtCore, QtGui, QtWidgets

class Highlighter(QtGui.QSyntaxHighlighter):
    def __init__(self,parent:QtGui.QTextDocument = None):
        super().__init__(parent)
        self.initFormat()
        self.initRegexp()

    def initFormat(self):
        self.keyword_format = QtGui.QTextCharFormat()
        self.keyword_format.setForeground(QtCore.Qt.blue)
        self.keyword_format.setFontWeight(QtGui.QFont.Bold)

    def initRegexp(self):
        self.rule = QtCore.QRegularExpression(r"\[(?:TITLE|MAIN)\]")

    def highlightBlock(self, text): #highlightBlock 是必须重定义的自运行函数。
        i = self.rule.globalMatch(text)
        while i.hasNext():
            match = i.next()
            self.setFormat(match.capturedStart(),match.capturedLength(), self.keyword_format)

class TemplateEdit(QtWidgets.QPlainTextEdit):
    def __init__(self,parent=None):
        super().__init__(parent)
        self.highlighter = Highlighter(self.document())
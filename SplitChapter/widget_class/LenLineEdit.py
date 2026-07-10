from pyqt_import import QtWidgets

class LenLineEdit(QtWidgets.QLineEdit):
    def __init__(self,parent = None):
        super().__init__(parent)
    def focusOutEvent(self,event):
        super().focusOutEvent(event)
        self.parent().reflash_highlight()
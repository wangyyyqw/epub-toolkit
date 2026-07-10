
from pyqt_import import QtWidgets

class ImporterLineEdit(QtWidgets.QLineEdit):
    def __init__(self,parent = None):
        super().__init__(parent)
        self.url = ''
    def dragEnterEvent(self, event):
        if event.mimeData().hasUrls() and len(event.mimeData().urls()) == 1:
            url = event.mimeData().urls()[0].url()
            if url.lower().endswith('.txt'):
                self.url = url
                event.accept()
        else:
            event.ignore()
    def dropEvent(self, event):
        super().dropEvent(event)
        open_filedialog = self.parent().parent().open_filedialog
        open_filedialog(self.url[8:])
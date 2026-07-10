import os

e = os.environ.get('SIGIL_QT_RUNTIME_VERSION', '6.5.2')
SIGIL_QT_MAJOR_VERSION = tuple(map(int, (e.split("."))))[0]

if SIGIL_QT_MAJOR_VERSION == 6:
    from PySide6 import QtWidgets,QtGui,QtCore
    from PySide6.QtCore import Signal,Slot
    import main_ui.main_ui_qt6 as main_ui
    import main_ui.treeview_qt6 as treeview
    import main_ui.edit_regexp_qt6 as edit_regexp
    import main_ui.template_box_qt6 as template_box
elif SIGIL_QT_MAJOR_VERSION == 5:
    from PyQt5 import QtWidgets,QtGui,QtCore
    from PyQt5.QtCore import pyqtSignal as Signal
    from PyQt5.QtCore import pyqtSlot as Slot
    import main_ui.main_ui as main_ui
    import main_ui.treeview as treeview
    import main_ui.edit_regexp as edit_regexp
    import main_ui.template_box as template_box
    
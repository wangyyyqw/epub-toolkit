if exist main_ui.ui pyside6-uic.exe main_ui.ui -o main_ui_qt6.py
if exist treeview.ui pyside6-uic.exe treeview.ui -o treeview_qt6.py
if exist edit_regexp.ui pyside6-uic.exe edit_regexp.ui -o edit_regexp_qt6.py
if exist template_box.ui pyside6-uic.exe template_box.ui -o template_box_qt6.py
if exist res.qrc pyside6-rcc.exe -o res_rc.py res.qrc
pause

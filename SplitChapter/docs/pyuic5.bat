if exist main_ui.ui pyuic5.exe main_ui.ui -o main_ui.py
if exist treeview.ui pyuic5.exe treeview.ui -o treeview.py
if exist edit_regexp.ui pyuic5.exe edit_regexp.ui -o edit_regexp.py
if exist template_box.ui pyuic5.exe template_box.ui -o template_box.py
if exist res.qrc pyrcc5.exe -o res_rc.py res.qrc
pause
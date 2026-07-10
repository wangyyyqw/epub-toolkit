from pyqt_import import QtCore, QtGui, QtWidgets
from tools.turn_number import cn_turn_arab
import re



class PreviewItemDelegate(QtWidgets.QStyledItemDelegate):
    def setEditorData(self, editor: QtWidgets.QLineEdit, index: QtCore.QModelIndex) -> None:
        editor.setReadOnly(True)
        editor.setStyleSheet('''
        QLineEdit {
            border:0px solid black; 
            color:rgba(0,0,0,0);
            selection-color:white;
            background-color:rgba(0,0,0,0);
        }
        QLineEdit:
        ''')
        super().setEditorData(editor, index)

class PreviewTreeWidget(QtWidgets.QTreeWidget):
    def __init__(self, parent):
        super().__init__(parent)
        self.mainform = self.parent().parent()
        self.seq_check_switch = False
        self.titles = [] # 储存每行标题的级别和标题名称
        self.title_numbers = [] # 储存每行标题包含数字
        self.chapter_length_check = False
        self.all_items:list[QtWidgets.QTreeWidgetItem] = []
        self.max_chapter_length = 0
        self.setEditTriggers(QtWidgets.QAbstractItemView.EditTrigger.DoubleClicked)
        self.setItemDelegateForColumn(0,PreviewItemDelegate(self))

    def build_tree(self,titles):
        self.titles = titles
        
        last_lv = 9
        
        count = 0
        for lv,title in titles:
            lv = int(lv)
            if last_lv == 9:
                parent = None
            elif lv < last_lv:
                parent = item
                i = last_lv - lv
                while i > 0:
                    i -= 1
                    try:
                        parent = parent.parent().parent()
                    except:
                        parent = None
            elif lv > last_lv:
                parent = item
            item = QtWidgets.QTreeWidgetItem(parent)
            item.setFlags(QtCore.Qt.ItemIsEditable|item.flags())
            item.setText(0,title)
            item.setData(2,0,count)
            count += 1
            if len(title) > self.parent().length_limit:
                #设前景高亮，背景设在QSS且QSS权值更高，所以这里设前景高亮
                item.setForeground(0,QtGui.QColor(255,0,0))
                
            if parent == None:
                self.addTopLevelItem(item)
                    
            self.all_items.append(item)
            
            last_lv = lv

        self.expandAll()

    def reflash_highlight(self,length_limit):
        for item in self.all_items:
            title = item.data(0,0)
            if len(title) > length_limit:
                item.setForeground(0,QtGui.QColor(255,0,0))
            else:
                item.setForeground(0,QtGui.QColor(0,0,0))

    def expand_all(self):
        self.expandAll()
    def fold_all(self):
        self.collapseAll()
    
    def seq_check(self):
        if self.seq_check_switch == False:
            self.seq_check_switch = True
            self.parent().seqcheck_button.setText('ON')
        else:
            self.seq_check_switch = False
            self.parent().seqcheck_button.setText('OFF')
            self.reflash_highlight(self.parent().length_limit)
            return

        if self.title_numbers == []:
            titles_count = len(self.titles)
            if titles_count == 0: #没有标题则返回
                return
            re_number = re.compile(r'\d+|[一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟萬〇零]+')

            for i in range(titles_count): #初始化 self.title_numbers
                title = self.titles[i][1]
                #中文数字转阿拉伯数字
                numstr = re_number.search(title)
                if numstr is not None:
                    if numstr[0] > 'A':
                        number = cn_turn_arab(numstr.group())
                    else:
                        number = int(numstr.group())
                    if not isinstance(number,int):
                        number = -1
                    else:
                        pass
                else:
                    number = -1

                self.title_numbers.append(number) 

        lv_list = [lv for lv,title in self.titles]
        seqcheck_work_data = list(zip(self.title_numbers,lv_list,self.all_items)) # [(num,lv,item)]
        
        titles_count = len(seqcheck_work_data)
        seqcheck_work_data.sort(key=lambda x:x[1],reverse=False)

        color = ['#FF0033','#FF3300','#FF0099','#990099','#990099','#990099','#990099']
        for i in range(1,titles_count):
            num = seqcheck_work_data[i][0]
            lv = seqcheck_work_data[i][1]
            last_num = seqcheck_work_data[i-1][0]
            last_lv = seqcheck_work_data[i-1][1]
            item = seqcheck_work_data[i][2]
            item.setForeground(0,QtGui.QColor('#005500'))
            if lv != last_lv:
                color.pop(0)
                continue
            if num > 0 and last_num >= 0 and num - last_num == 1: #章节
                continue
            elif num == 0 or num == 1:
                continue
            else:
                item.setForeground(0,QtGui.QColor(color[0]))
        item = seqcheck_work_data[0][2]
        item.setForeground(0,QtGui.QColor('#005500'))
        
    def drawChapterLengthBarChart(self,chapterLengthList):
        if self.chapter_length_check == True:
            return self.viewport().update()
        
        self.setColumnCount(2)
        self.setHeaderHidden(False)
        self.setHeaderLabels([" 章节名"," 章节字数"])
        self.chapter_length_list = chapterLengthList
        self.setColumnWidth(0,250)
        self.parent().resize(550,self.parent().height())
        
        i = 0
        for item in self.all_items:
            item.setData(1,0,str(chapterLengthList[i]))
            i += 1
                    
        for length in self.chapter_length_list:
            if self.max_chapter_length < length:
                self.max_chapter_length = length
        
        self.chapter_length_check = True
        self.viewport().update()
   
    def mouseDoubleClickEvent(self, e : QtGui.QMouseEvent):
        if self.currentColumn() == 1:
            return
        if e.button() == QtCore.Qt.MouseButton.LeftButton:
            return super().mouseDoubleClickEvent(e)


    def mouseReleaseEvent(self, e: QtGui.QMouseEvent) -> None:
        if e.button() == QtCore.Qt.MouseButton.LeftButton:
            return super().mouseReleaseEvent(e)

        item = self.itemAt(e.pos())
        if not item:
            return
        
        self.setCurrentItem(item)
        mindex = self.indexFromItem(item,0)
        rect = self.visualRect(mindex)
        if e.pos().x() < rect.topLeft().x() or \
           e.pos().x() > rect.topRight().x():
            return
        
        order = item.data(2,0) 
        if order in self.mainform.ignore_title['ignore_position']:
            item.setFlags(item.flags() | QtCore.Qt.ItemIsEditable)
            self.mainform.ignore_title['ignore_position'].remove(order)
        else:
            item.setFlags(item.flags() ^ QtCore.Qt.ItemIsEditable)
            self.mainform.ignore_title['ignore_position'].append(order)
            
        self.viewport().update()
        return super().mouseReleaseEvent(e)

    def paintEvent(self, e: QtGui.QPaintEvent) -> None:
        
        super().paintEvent(e)
        
        if not self.chapter_length_check and len(self.mainform.ignore_title['ignore_position']) == 0:
            return
        
        painter = QtGui.QPainter(self.viewport())
        
        if len(self.mainform.ignore_title['ignore_position']) > 0:
            pen = QtGui.QPen(QtGui.QColor(255,0,0),1.8)
            painter.setPen(pen)
            for order in self.mainform.ignore_title['ignore_position']:
                item = self.all_items[order]
                mindex = self.indexFromItem(item,0)
                rect = self.visualRect(mindex)
                y = rect.center().y()
                x1 = rect.topLeft().x()
                x2 = rect.topRight().x() - 8
                painter.drawLine(x1,y,x2,y)
                
        if self.chapter_length_check:
            black_color = QtGui.QColor(0,0,0)
            bold_pen = QtGui.QPen(black_color,0.5)
            thin_pen = QtGui.QPen(QtGui.QColor(63,133,255),0.1)
            white_brush = QtGui.QBrush(QtGui.QColor(255,255,255))
            blue_brush = QtGui.QBrush(QtGui.QColor(63,133,255))

            for item in self.all_items:
                chapter_len = int(item.data(1,0))
                mindex = self.indexFromItem(item,1)
                rect = self.visualRect(mindex)
                x,y,w,h = rect.x(),rect.y(),rect.width(),rect.height()
                
                painter.setPen(bold_pen)
                painter.setBrush(white_brush)
                painter.drawRect(QtCore.QRect(x,y,w,h))
                painter.setPen(thin_pen)
                painter.setBrush(blue_brush)
                r = chapter_len/self.max_chapter_length
                painter.drawRect(QtCore.QRectF(x+1,y+1,w*r,h-2))
                painter.setPen(black_color)
                painter.drawText(x+3,y+1,w-1,h-2,QtCore.Qt.AlignmentFlag.AlignVCenter,str(chapter_len))
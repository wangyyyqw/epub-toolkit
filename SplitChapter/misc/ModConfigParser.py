
import configparser
class ModConfigParser(configparser.ConfigParser):
    def optionxform(self,optionstr):
        #重定义 ConfigParser 的 optionxform 函数，取消其 option 强制小写的特性。
        return optionstr
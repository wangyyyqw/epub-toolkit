
BLANK_CHARS = "\r\n\t\x20\xa0\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u200b\u200c\u200d\u202f\u2060\u3000\ufeff"

DEFAULT_REGEXPS = [
(1,"^\\s*第[一二三四五六七八九十零〇百千两]+卷.*$"),
(1,"^\\s*第[一二三四五六七八九十零〇百千两]+部.*$"),
(2,"^\\s*第[一二三四五六七八九十零〇百千两]+章.*$"),
(2,"^\\s*第[一二三四五六七八九十零〇百千两]+回.*$"),
(2,"^\\s*第[一二三四五六七八九十零〇百千两]+节.*$"),
(2,"^\\s*第[一二三四五六七八九十零〇百千两]+集.*$"),
(1,"^\\s*第\\d+卷.*$"),
(1,"^\\s*第\\d+部.*$"),
(2,"^\\s*第\\d+章.*$"),
(2,"^\\s*第\\d+回.*$"),
(2,"^\\s*第\\d+节.*$"),
(2,"^\\s*第\\d+集.*$"),
(1,"^\\s*卷[一二三四五六七八九十零〇]+.*$"),
(2,"^\\s*(序[1-9言曲]?|(内容)?简介|后记|尾声)$"),
(2,"^\\s*\\d+\\s*$"),
(3,"^[一二三四五六七八九十〇]+$")
]
DEFAULT_NAMERULES = [
"default:Chapter{0000}",
"h1:Vol{00} | h2:Chapter{0000}",
"h1:Vol{00} | h2:{h1}-Chapter{$$$}",
"default:Section{0000} | h1,h2,h3,h4,h5,h6:Chapter{0000}"
]

DEFAULT_TEMPLATE = '''\
<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"
  "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">

<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head>
  <title>[TITLE]</title>
  <link href="../Styles/Style0001.css" type="text/css" rel="stylesheet"/>
</head>
<body>
  [MAIN]
</body>
</html>
'''
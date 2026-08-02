/// 批注 CSS 样式工具类
///
/// 提供 `buildCommentCss` 方法和 `cssMarker` 常量，
/// 供 `FootnoteToCommentOperation` 注入悬浮批注样式时使用。
///
/// CSS 中 `background-image: url()` 路径是相对于 CSS 文件自身位置的，
/// 因此不能写死固定路径，必须由调用方根据 CSS 文件实际位置动态计算后传入。
class CommentOperation {
  CommentOperation._();

  /// 批注 CSS 样式标记（用于检测是否已注入）
  static const cssMarker = '/* ========== 正则注释样式 ========== */';

  /// 生成批注 CSS 样式内容
  ///
  /// [notePngRelPath] note.png 相对于 CSS 文件所在目录的路径。
  /// CSS 中 url() 路径是相对于 CSS 文件自身位置的,
  /// 不能写死 ../Images/note.png,必须根据每个 CSS 文件的实际位置计算。
  static String buildCommentCss(String notePngRelPath) {
    return '''
$cssMarker
span.reader {
    position: relative;
    display: inline-block;
    width: 19px;
    height: 19px;
    vertical-align: sub;
    cursor: pointer;
    margin: 0 3px;
    background-image: url("$notePngRelPath");
    background-size: 100%;
    background-repeat: no-repeat;
}

span.reader:hover:after {
    content: attr(data-wr-footernote);
    position: fixed;
    left: 0;
    bottom: 0;
    margin: 1em;
    background: black;
    border-radius: 0.25em;
    color: white;
    padding: 0.5em;
    font-size: 1em;
    font-family: "南构明史稿鉴", sans-serif;
    z-index: 10;
    text-indent: 0em;
}
''';
  }
}

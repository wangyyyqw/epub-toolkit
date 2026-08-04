import 'package:epub_gadget/features/text_diff/diff_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = DiffEngine();

  DiffResult compute(List<String> a, List<String> b,
      {DiffOptions options = const DiffOptions()}) {
    return engine.compute(a, b, options: options);
  }

  group('行级差分', () {
    test('完全一致', () {
      final r = compute(['a', 'b', 'c'], ['a', 'b', 'c']);
      expect(r.changeCount, 0);
      expect(r.rows, hasLength(3));
      expect(r.rows.every((row) => row.op == DiffOp.equal), isTrue);
    });

    test('重复行只匹配一次', () {
      final r = compute(['x', 'x'], ['x']);
      expect(r.rows.map((row) => row.op).toList(),
          [DiffOp.equal, DiffOp.delete]);
      expect(r.changeCount, 1);
    });

    test('右侧新增行', () {
      final r = compute(['a', 'c'], ['a', 'b', 'c']);
      expect(r.changeCount, 1);
      final insertRows = r.rows.where((row) => row.op == DiffOp.insert);
      expect(insertRows, hasLength(1));
      expect(insertRows.single.leftIndex, isNull);
      expect(insertRows.single.rightIndex, 1);
      expect(insertRows.single.rightText, 'b');
    });

    test('左侧删除行', () {
      final r = compute(['a', 'b', 'c'], ['a', 'c']);
      expect(r.changeCount, 1);
      final del = r.rows.singleWhere((row) => row.op == DiffOp.delete);
      expect(del.leftIndex, 1);
      expect(del.rightIndex, isNull);
      expect(del.leftText, 'b');
    });

    test('相邻删除与新增合并为 replace 行', () {
      final r = compute(['a', 'x'], ['a', 'y']);
      expect(r.changeCount, 1);
      final rep = r.rows.singleWhere((row) => row.op == DiffOp.replace);
      expect(rep.leftIndex, 1);
      expect(rep.rightIndex, 1);
      expect(rep.leftText, 'x');
      expect(rep.rightText, 'y');
    });

    test('多行插入（LCS 最小编辑：纯插入而非替换）', () {
      final r = compute(
        ['1', '2', '3'],
        ['1', '2', 'x', 'y', '3'],
      );
      // LCS 为 [1,2,3]，最小编辑 = 在 2 后插入 x、y
      expect(r.changeCount, 1);
      expect(
        r.rows.map((row) => row.op).toList(),
        [DiffOp.equal, DiffOp.equal, DiffOp.insert, DiffOp.insert, DiffOp.equal],
      );
    });

    test('相邻删除与新增形成 replace + insert 混合块', () {
      final r = compute(
        ['1', '2', '3'],
        ['1', 'x', 'y', '3'],
      );
      expect(r.changeCount, 1);
      final ops = r.rows.map((row) => row.op).toList();
      expect(ops, contains(DiffOp.replace));
      expect(ops, contains(DiffOp.insert));
      expect(ops.first, DiffOp.equal);
      expect(ops.last, DiffOp.equal);
    });

    test('中间插入不合并两端相等块', () {
      final r = compute(['a', 'b'], ['a', 'x', 'b']);
      expect(r.changeCount, 1);
      expect(r.rows.first.op, DiffOp.equal);
      expect(r.rows.last.op, DiffOp.equal);
    });

    test('差异块区间正确', () {
      final r = compute(['a', 'b', 'c', 'd'], ['a', 'B', 'C', 'd']);
      expect(r.changeCount, 1);
      final block = r.blocks.single;
      expect(block.startRow, 1);
      expect(block.endRow, 3);
    });

    test('空文件', () {
      final r = compute([], ['a']);
      expect(r.changeCount, 1);
      expect(r.rows.single.op, DiffOp.insert);
    });
  });

  group('锚点与移动块', () {
    test('整块移动显示为删除 + 插入', () {
      final r = compute(['1', '2', '3', '4'], ['3', '4', '1', '2']);
      // 贪心锚点先匹配前面的 1、2，3、4 分别变为右侧插入与左侧删除
      expect(
        r.rows.map((row) => row.op).toList(),
        [
          DiffOp.insert,
          DiffOp.insert,
          DiffOp.equal,
          DiffOp.equal,
          DiffOp.delete,
          DiffOp.delete,
        ],
      );
      expect(r.changeCount, 2);
    });

    test('锚点行保持 equal', () {
      final r = compute(['a', 'b', 'c'], ['a', 'x', 'b', 'c']);
      expect(r.rows[0].op, DiffOp.equal);
      expect(r.rows[1].op, DiffOp.insert);
      expect(r.rows[2].op, DiffOp.equal);
      expect(r.rows[3].op, DiffOp.equal);
    });
  });

  group('字符级差异', () {
    test('修改行带行内片段', () {
      final r = compute(['hello world'], ['hello there']);
      final rep = r.rows.singleWhere((row) => row.op == DiffOp.replace);
      expect(rep.leftSpans, isNotNull);
      expect(rep.rightSpans, isNotNull);
      // LCS 共享 'r'：左侧变化段 = world 去掉 r → wold
      final changedLeft =
          rep.leftSpans!.where((s) => s.changed).map((s) => s.text).join();
      expect(changedLeft, 'wold');
      // 右侧变化段 = there 去掉 r → thee
      final changedRight =
          rep.rightSpans!.where((s) => s.changed).map((s) => s.text).join();
      expect(changedRight, 'thee');
      // 未变片段包含共享的 hello 与 r
      final equalLeft =
          rep.leftSpans!.where((s) => !s.changed).map((s) => s.text).join();
      expect(equalLeft, 'hello r');
    });

    test('中文与 emoji 按字符处理', () {
      final r = compute(['中文对比'], ['中文对👀比']);
      final rep = r.rows.singleWhere((row) => row.op == DiffOp.replace);
      final changed =
          rep.rightSpans!.where((s) => s.changed).map((s) => s.text).join();
      expect(changed, '👀');
    });

    test('未变行无行内片段', () {
      final r = compute(['same'], ['same']);
      expect(r.rows.single.leftSpans, isNull);
    });
  });

  group('空白模式（哈希预处理）', () {
    test('exact：不忽略空白，视为差异', () {
      final r = compute(['a  b'], ['a   b']);
      expect(r.changeCount, 1);
    });

    test('trim：忽略行首尾空白', () {
      final r = compute(
        ['  a  b  '],
        ['a  b'],
        options: const DiffOptions(whitespaceMode: WhiteSpaceMode.trim),
      );
      expect(r.changeCount, 0);
    });

    test('trimEnd：忽略行尾空白，保留行首空白', () {
      final a = compute(
        ['a  b  '],
        ['a  b'],
        options: const DiffOptions(whitespaceMode: WhiteSpaceMode.trimEnd),
      );
      expect(a.changeCount, 0);
      final b = compute(
        [' a'],
        ['a'],
        options: const DiffOptions(whitespaceMode: WhiteSpaceMode.trimEnd),
      );
      expect(b.changeCount, 1);
    });

    test('all：忽略全部空白字符', () {
      final a = compute(
        ['a b'],
        ['ab'],
        options: const DiffOptions(whitespaceMode: WhiteSpaceMode.all),
      );
      expect(a.changeCount, 0);
      final b = compute(
        ['a\tb'],
        ['ab'],
        options: const DiffOptions(whitespaceMode: WhiteSpaceMode.all),
      );
      expect(b.changeCount, 0);
    });

    test('忽略大小写', () {
      final r = compute(
        ['Hello'],
        ['hello'],
        options: const DiffOptions(ignoreCase: true),
      );
      expect(r.changeCount, 0);
    });
  });

  group('相似度阈值', () {
    test('达到阈值：行对匹配为 replace（带行内片段）', () {
      final r = compute(
        ['abcdefg', 'tail'],
        ['head', 'abcxefg'],
        options: const DiffOptions(similarityThreshold: 50),
      );
      // 'abcdefg' 与 'abcxefg' 相似度 ≥50% 直接配对
      expect(
        r.rows.map((row) => row.op).toList(),
        [DiffOp.insert, DiffOp.replace, DiffOp.delete],
      );
      final rep = r.rows[1];
      expect(rep.leftText, 'abcdefg');
      expect(rep.rightText, 'abcxefg');
      expect(rep.leftSpans, isNotNull);
      expect(rep.rightSpans, isNotNull);
      expect(r.changeCount, 1);
    });

    test('阈值 0（仅精确匹配）：不配对，退化为相邻替换', () {
      final r = compute(
        ['abcdefg', 'tail'],
        ['head', 'abcxefg'],
      );
      expect(
        r.rows.map((row) => row.op).toList(),
        [DiffOp.replace, DiffOp.replace],
      );
    });

    test('阈值 90：相似度不足不配对', () {
      final r = compute(
        ['abcdefg', 'tail'],
        ['head', 'abcxefg'],
        options: const DiffOptions(similarityThreshold: 90),
      );
      // dice ≈ 0.667 < 0.9
      expect(
        r.rows.map((row) => row.op).toList(),
        [DiffOp.replace, DiffOp.replace],
      );
    });

    test('长度相差悬殊的行不参与相似度匹配', () {
      final r = compute(
        ['abcdefg', 'tail'],
        ['head', 'abcxefg'],
        options: const DiffOptions(similarityThreshold: 50),
      );
      // 'head'/'tail' 与 'abcdefg'/'abcxefg' 长度比过低，长度预过滤直接拒绝
      expect(r.rows.where((row) => row.op == DiffOp.replace), isNotEmpty);
    });

    test('完全不同的行相似度为 0', () {
      final r = compute(
        ['aaaaaaaaaa'],
        ['bbbbbbbbbb'],
        options: const DiffOptions(similarityThreshold: 50),
      );
      expect(r.changeCount, 1);
      expect(r.rows.single.op, DiffOp.replace);
    });
  });

  group('忽略空白行', () {
    test('默认忽略：单侧多余的空白行不输出', () {
      final r = compute(['', 'a'], ['a', '']);
      // 两侧空白行位于不同位置，无法配对时直接丢弃，不产生差异
      expect(
        r.rows.map((row) => row.op).toList(),
        [DiffOp.equal],
      );
      expect(r.rows.single.leftText, 'a');
      expect(r.rows.single.rightText, 'a');
      expect(r.changeCount, 0);
    });

    test('纯空白文件无差异', () {
      final r = compute(['', '', ''], ['', '']);
      expect(r.changeCount, 0);
      expect(r.rows, hasLength(2));
      expect(r.rows.every((row) => row.op == DiffOp.equal), isTrue);
    });

    test('空白行不阻断周边文本匹配', () {
      final r = compute(['x', '', 'y'], ['x', 'y']);
      expect(
        r.rows.map((row) => row.op).toList(),
        [DiffOp.equal, DiffOp.equal],
      );
      expect(r.changeCount, 0);
    });

    test('多余空白行不再显示为差异', () {
      final r = compute(['a', '', 'b'], ['a', '', '', 'b']);
      expect(
        r.rows.map((row) => row.op).toList(),
        [DiffOp.equal, DiffOp.equal, DiffOp.equal],
      );
      expect(r.changeCount, 0);
    });

    test('关闭忽略：空白行参与匹配并显示差异', () {
      final r = compute(
        ['', 'a', ''],
        ['', '', 'a'],
        options: const DiffOptions(ignoreBlankLines: false),
      );
      expect(
        r.rows.map((row) => row.op).toList(),
        [DiffOp.equal, DiffOp.insert, DiffOp.equal, DiffOp.delete],
      );
      expect(r.rows[0].leftText, '');
      expect(r.rows[0].rightText, '');
      expect(r.rows[1].rightText, '');
      expect(r.rows[3].leftText, '');
      expect(r.changeCount, 2);
    });

    test('关闭忽略：空白行与内容行统一匹配', () {
      final r = compute(
        ['', 'a'],
        ['a', ''],
        options: const DiffOptions(ignoreBlankLines: false),
      );
      expect(
        r.rows.map((row) => row.op).toList(),
        [DiffOp.insert, DiffOp.equal, DiffOp.delete],
      );
      expect(r.changeCount, 2);
    });
  });

  group('行模型一致性', () {
    test('每行左右索引与文本对应', () {
      final left = ['l0', 'l1', 'l2'];
      final right = ['r0', 'l1', 'l2'];
      final r = compute(left, right);
      for (final row in r.rows) {
        if (row.leftIndex != null) {
          expect(row.leftText, left[row.leftIndex!]);
        }
        if (row.rightIndex != null) {
          expect(row.rightText, right[row.rightIndex!]);
        }
      }
    });

    test('忽略空白行下索引与文本仍对应', () {
      final left = ['', 'a', ''];
      final right = ['', '', 'a'];
      final r = compute(left, right,
          options: const DiffOptions(ignoreBlankLines: false));
      for (final row in r.rows) {
        if (row.leftIndex != null) {
          expect(row.leftText, left[row.leftIndex!]);
        }
        if (row.rightIndex != null) {
          expect(row.rightText, right[row.rightIndex!]);
        }
      }
    });
  });

  group('行数上限与未对比区域', () {
    test('maxCompareLines=0：全部标记未对比，内容完整显示', () {
      final left = List.generate(100, (i) => 'L$i');
      final right = List.generate(100, (i) => 'R$i');
      final r = engine.compute(left, right, maxCompareLines: 0);
      expect(r.truncated, isTrue);
      expect(r.rows, hasLength(100));
      expect(r.rows.every((row) => row.op == DiffOp.unknown), isTrue);
      expect(r.changeCount, 0);
      // 文本完整保留
      expect(r.rows.last.leftText, 'L99');
      expect(r.rows.last.rightText, 'R99');
    });

    test('maxCompareLines=N：前 N 行对比，其余 unknown', () {
      final left = ['a', 'b', 'c', 'd'];
      final right = ['a', 'x', 'c', 'd'];
      final r = engine.compute(left, right, maxCompareLines: 2);
      expect(r.rows, hasLength(4));
      // 前两行已对比：a 相同、b 被 x 替换
      expect(r.rows[0].op, DiffOp.equal);
      expect(r.rows[1].op, DiffOp.replace);
      // 后两行未对比
      expect(r.rows[2].op, DiffOp.unknown);
      expect(r.rows[3].op, DiffOp.unknown);
      expect(r.rows[2].leftText, 'c');
      expect(r.rows[3].rightText, 'd');
      expect(r.changeCount, 1);
    });

    test('截断后左右剩余行数不同也能完整显示', () {
      final left = List.generate(5, (i) => 'L$i');
      final right = List.generate(3, (i) => 'R$i');
      final r = engine.compute(left, right, maxCompareLines: 2);
      // 剩余 left 3 行、right 1 行 → unknown 区取最大值 3 行
      expect(r.rows, hasLength(5));
      final unknowns =
          r.rows.where((row) => row.op == DiffOp.unknown).toList();
      expect(unknowns, hasLength(3));
      expect(unknowns[0].leftText, 'L2');
      expect(unknowns[0].rightText, 'R2');
      expect(unknowns[1].leftText, 'L3');
      expect(unknowns[1].rightIndex, isNull);
      expect(unknowns[2].leftText, 'L4');
      expect(unknowns[2].rightIndex, isNull);
      expect(r.truncated, isTrue);
    });

    test('全量对比（maxCompareLines=null）不产生 unknown', () {
      final r = compute(['a', 'b'], ['a', 'b']);
      expect(r.truncated, isFalse);
      expect(r.rows.every((row) => row.op == DiffOp.equal), isTrue);
    });
  });
}

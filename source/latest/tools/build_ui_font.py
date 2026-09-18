# -*- coding: utf-8 -*-
from pathlib import Path
import sys
sys.path=[p for p in sys.path if Path(p).resolve()!=Path(__file__).resolve().parent]
from fontTools import subset
R=Path(__file__).resolve().parents[3]
font=subset.load_font(str(R/'source/latest/fonts/NotoSansCJKsc-Regular.otf'),subset.Options())
text=''.join(p.read_text() for folder in ['scripts','data'] for p in (R/folder).rglob('*') if p.suffix in ['.gd','.json'])+''.join(chr(i) for i in range(32,127))
s=subset.Subsetter();s.populate(text=text);s.subset(font)
# Rename subset, preserving original copyright/license name records.
for n in font['name'].names:
 if n.nameID in (1,2,3,4,6,16,17):
  name='Regular' if n.nameID in (2,17) else 'DeskfrontUI'
  n.string=name.encode(n.getEncoding())
subset.save_font(font,str(R/'assets/fonts/DeskfrontUI.otf'),subset.Options())

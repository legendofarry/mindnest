import sys
from pathlib import Path

p = Path(r'c:\Users\karim\Documents\work\mindnest\lib\core\ui\auth_desktop_shell.dart')
text = p.read_text(encoding='utf-8')
stack = []
pairs = {')':'(', ']':'[', '}':'{'}
line = 1
col = 0
for i,ch in enumerate(text):
    if ch=='\n':
        line +=1
        col = 0
        continue
    col +=1
    if ch in '([{':
        stack.append((ch,line,col))
    elif ch in ')]}':
        if not stack:
            print(f"Unmatched closing {ch} at {line}:{col}")
            sys.exit(1)
        top, l, c = stack.pop()
        if top != pairs[ch]:
            print(f"Mismatched {top} (opened at {l}:{c}) closed by {ch} at {line}:{col}")
            # show context
            lines = text.splitlines()
            start = max(0, l-4)
            end = min(len(lines), line+3)
            print('\nContext around opening:')
            for idx in range(start, start+8):
                if idx < len(lines):
                    print(f"{idx+1}: {lines[idx]}")
            print('\nContext around closing:')
            for idx in range(max(0, line-4), min(len(lines), line+3)):
                print(f"{idx+1}: {lines[idx]}")
            sys.exit(1)

if stack:
    print('Unclosed opening brackets:')
    for ch,l,c in stack:
        print(f" {ch} opened at {l}:{c}")
    sys.exit(1)

print('All brackets balanced')

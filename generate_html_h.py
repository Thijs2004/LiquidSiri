import re

with open('siri-wave.html', 'r') as f:
    content = f.read()

# 1. Remove UI
content = re.sub(r'<div id="seg">.*?</div>', '', content, flags=re.DOTALL)
content = re.sub(r'<div id="err"></div>', '', content)
content = re.sub(r'document\.querySelectorAll.*?}\);', '', content, flags=re.DOTALL)

# 2. Make transparent
content = content.replace('background:#0a0a0c', 'background:transparent')
content = content.replace('background:#000', 'background:transparent')
content = content.replace("canvas.getContext('webgl')", "canvas.getContext('webgl', {alpha:true})")

# 3. Fix shader alpha
content = content.replace('fragColor = vec4(col, 1.0);', 'float a = max(col.r, max(col.g, col.b)); fragColor = vec4(col, a);')

# 4. Fix CSS size
content = re.sub(r'#gl \{.*?\}', '#gl { display:block; width:100vw; height:100vh; background:transparent; }', content, flags=re.DOTALL)

# 5. Fix JS resize
content = content.replace('const css=420;', 'const css=window.innerWidth;')

# 6. Escape for ObjC string
lines = content.split('\n')
objc_str = 'static NSString * const siriWaveHTML = @""\n'
for line in lines:
    line = line.replace('\\', '\\\\').replace('"', '\\"')
    objc_str += f'"{line}\\n"\n'
objc_str += ';\n'

with open('SiriWaveHTML.h', 'w') as f:
    f.write(objc_str)


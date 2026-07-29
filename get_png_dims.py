from PIL import Image
import os

files = [
    '/Users/pounds_1/dev/Textractor/Sources/Textractor/Resources/textractor-splash.png',
    '/Users/pounds_1/dev/Textractor/Sources/Textractor/Resources/textractor-type.png',
    '/Users/pounds_1/dev/Textractor/Sources/Textractor/Resources/MenuBar/textractor-menubar@2x.png',
    '/Users/pounds_1/dev/Textractor/Sources/Textractor/Resources/MenuBar/textractor-menubar@1x.png',
    '/Users/pounds_1/dev/Textractor/icons/textractor Exports/textractor-watchOS-Default-1088@1x.png',
    '/Users/pounds_1/dev/Textractor/icons/textractor Exports/textractor-iOS-TintedLight-1024@1x.png',
    '/Users/pounds_1/dev/Textractor/icons/textractor Exports/textractor-iOS-TintedDark-1024@1x.png',
    '/Users/pounds_1/dev/Textractor/icons/textractor Exports/textractor-iOS-Default-1024@1x.png',
    '/Users/pounds_1/dev/Textractor/icons/textractor Exports/textractor-iOS-Dark-1024@1x.png',
    '/Users/pounds_1/dev/Textractor/icons/textractor Exports/textractor-iOS-ClearLight-1024@1x.png',
    '/Users/pounds_1/dev/Textractor/icons/textractor Exports/textractor-iOS-ClearDark-1024@1x.png',
]

for f in files:
    try:
        with Image.open(f) as img:
            print(f'{os.path.basename(f)}: {img.size[0]}x{img.size[1]}')
    except Exception as e:
        print(f'{os.path.basename(f)}: Error - {e}')
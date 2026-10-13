from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageChops
SIZE=(190,290)
ink='#11152f';pink='#f4a0bf';shadow='#e47da5';light='#ffd1df'
canvas=Image.new('RGBA',SIZE)
d=ImageDraw.Draw(canvas)
# Rounded shoes sit behind the body.
for box in [(14,240,92,276),(98,240,176,276)]:
    d.ellipse(box,fill=ink)
    x0,y0,x1,y1=box
    d.ellipse((x0+3,y0+3,x1-3,y1-3),fill='#ca3e70')
    d.ellipse((x0+7,y0+4,x1-7,y1-8),fill='#e95889')
d.ellipse((26,247,36,254),fill='#ffadc6');d.ellipse((149,247,159,254),fill='#ffadc6')
# Unioned silhouette, not an egg: a circle and two rounded arms.
mask=Image.new('L',SIZE);m=ImageDraw.Draw(mask)
m.ellipse((5,70,47,139),fill=255) # raised left arm
m.ellipse((10,84,180,254),fill=255) # round body
m.ellipse((155,158,187,207),fill=255) # lower right arm
canvas.paste(ink,(0,0),mask)
inner=mask.filter(ImageFilter.MinFilter(7));canvas.paste(shadow,(0,0),inner)
main=Image.new('L',SIZE);md=ImageDraw.Draw(main)
md.ellipse((8,82,174,247),fill=255);md.ellipse((4,70,43,134),fill=255);md.ellipse((154,157,182,203),fill=255)
canvas.paste(pink,(0,0),ImageChops.multiply(main,inner))
d=ImageDraw.Draw(canvas)
# Small discrete highlights and arm crease, not gradients.
d.arc((9,76,40,132),105,235,fill=light,width=2)
d.arc((156,164,181,199),15,85,fill=light,width=2)
d.arc((8,105,67,166),203,244,fill=ink,width=2)
d.arc((147,168,181,203),53,108,fill=ink,width=2)
for x in (69,107):
    d.ellipse((x,108,x+18,144),fill=ink)
    eyeMask=Image.new('L',SIZE);ed=ImageDraw.Draw(eyeMask);ed.ellipse((x+3,111,x+15,141),fill=255)
    blue=Image.new('RGBA',SIZE);bd=ImageDraw.Draw(blue);bd.rectangle((x,129,x+18,144),fill='#164076');bd.ellipse((x+4,130,x+14,140),fill='#2d78b4')
    canvas.alpha_composite(Image.composite(blue,Image.new('RGBA',SIZE),eyeMask))
    d=ImageDraw.Draw(canvas);d.ellipse((x+4,111,x+13,124),fill='#fff8ed')
d.ellipse((46,139,66,151),fill='#ed7299');d.ellipse((124,139,144,151),fill='#ed7299')
# Ninety-five sprite pixels across: about three display pixels per cell at medium.
canvas=canvas.resize((95,145),Image.Resampling.NEAREST)
canvas.save(Path(__file__).with_name('skin-kirby.png'))
print('Generated rounded 95x145 transparent Kirby sprite')

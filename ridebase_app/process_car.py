from PIL import Image

def process_image():
    input_path = '/Users/farai/.gemini/antigravity/brain/9da1a2e0-bdd5-4677-b147-99d49d315e8d/car_marker_1778189387890.png'
    output_path = '/Users/farai/upgraded_spork/ridebase_app/assets/images/car_marker.png'

    img = Image.open(input_path).convert("RGBA")
    datas = img.getdata()

    newData = []
    for item in datas:
        # Change all white (also shades of white)
        # to transparent
        if item[0] > 240 and item[1] > 240 and item[2] > 240:
            newData.append((255, 255, 255, 0))
        else:
            newData.append(item)

    img.putdata(newData)

    # Get bounding box of non-transparent pixels
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)

    # Resize to a reasonable icon size (e.g., 64x128)
    img.thumbnail((128, 128), Image.Resampling.LANCZOS)
    img.save(output_path, "PNG")

if __name__ == '__main__':
    process_image()

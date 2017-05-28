require 'rubygems'
require 'sinatra'
require 'prawn'
require 'prawn/measurements'
require 'prawn/qrcode'
require 'prawn-svg'
require 'color'
require 'excon'
require 'rmagick'
require 'json'
require 'zlib'

include Prawn::Measurements

module Excon
  class Response
    def json!()
      puts body
      JSON.parse(body)
    end
  end
end

BACKEND_URL = 'https://inventory.waw.hackerspace.pl/api/1/'
CODE_PREFIX = "HTTP://I/"

def api(uri)
  Excon.get(BACKEND_URL + uri + "/").json!
end

def render_identicode(data, id, extent)
  pts = [[0, 0], [0, 1], [1, 1], [1, 0], [0, 0]]

  4.times do |n|
    color = Color::HSL.from_fraction((id % 6) / 6.0, 1.0, 0.3).html[1..6]
    id /= 6

    save_graphics_state do
      soft_mask do
        fill_color 'ffffff'
        polygon = [pts[n], [0.5, 0.5], pts[n+1]].map{ |v| [v[0]*bounds.height, v[1]*bounds.height] }
        fill_polygon(*(polygon))
      end

      print_qr_code data, stroke: false,
                          extent: extent, foreground_color: color,
                          pos: [bounds.left, bounds.top]
    end
  end

  fill_color '000000'
end

def render_label(label)

  label = api("labels/#{label}")

  pdf = Prawn::Document.new(page_size: [89, 36].map { |x| mm2pt(x) },
                            margin: [2, 2, 2, 6].map { |x| mm2pt(x) }) do
    font_families.update("DejaVuSans" => {
      normal: "fonts/DejaVuSans.ttf",
      italic: "fonts/DejaVuSans-Oblique.ttf",
      bold: "fonts/DejaVuSans-Bold.ttf",
      bold_italic: "fonts/DejaVuSans-BoldOblique.ttf"
    })

    font 'DejaVuSans'


    # Width of right side
    rw = bounds.height/2

    # Right side
    bounding_box([bounds.right - rw, bounds.top], :width => rw) do
      print_qr_code CODE_PREFIX + label['id'], stroke: false,
        foreground_color: '000000',
        extent: bounds.width, margin: 0, pos: bounds.top_left
    end

    # Left side
    bounding_box(bounds.top_left, :width => bounds.width-rw) do
      text_box label['item']['name'],
        size: 30, align: :center, valign: :center,
        inline_format: true, overflow: :shrink_to_fit
    end
  end

  pdf.render
end

set :bind, '0.0.0.0'

get '/api/1/preview/:label.pdf' do
  headers["Content-Type"] = "application/pdf; charset=utf8"
  render_label params["label"]
end

get '/api/1/preview/:label.png' do
  headers["Content-Type"] = "image/png"
  img = Magick::ImageList.new()
  img = img.from_blob(render_label(params["label"])){ self.density = 200 }.first
  img.format = 'png'
  img.background_color = 'white'
  img.to_blob
end

post '/api/1/print/:label' do
  temp = Tempfile.new('labelmaker')
  temp.write(render_label(params["label"]))
  temp.close
  system("lpr -P DYMO_LabelWriter_450 #{temp.path}")
end

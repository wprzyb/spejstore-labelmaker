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

BACKEND_URL = 'http://127.0.0.1:8000/api/1/'
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
  margin = 2

  label = api("labels/#{label}")

  pdf = Prawn::Document.new(page_size: [89, 36].map { |x| mm2pt(x) },
                            margin: mm2pt(margin)) do
    font_families.update("DejaVuSans" => {
      normal: "fonts/DejaVuSans.ttf",
      italic: "fonts/DejaVuSans-Oblique.ttf",
      bold: "fonts/DejaVuSans-Bold.ttf",
      bold_italic: "fonts/DejaVuSans-BoldOblique.ttf"
    })

    font 'DejaVuSans'

    svg IO.read("hsyrenka.svg"),
      position: :right, vposition: :bottom,
      height: 0.5*bounds.height

    print_qr_code CODE_PREFIX + label['id'], stroke: false,
      extent: mm2pt(36-2*margin), foreground_color: color,
      pos: [bounds.left, bounds.top]

    text_box label['item']['name'],
      size: 30, align: :center, valign: :center,
      inline_format: true,
      width: bounds.width - bounds.height - 8,
      height: bounds.height - 10,
      at: [bounds.left+bounds.height, bounds.top - 5],
      overflow: :shrink_to_fit
  end

  pdf.render
end

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

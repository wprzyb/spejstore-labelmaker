require 'rubygems'
require 'sinatra'
require 'rqrcode'
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

# module Prawn
#   module Text
#     module Formatted #:nodoc:
#       # @private
#       class LineWrap #:nodoc:
#         def whitespace()
#           # Wrap by these special characters as well
#           "&:/\\" +
#           "\s\t#{zero_width_space()}"
#         end
#       end
#     end
#   end
# end

module Excon
  class Response
    def json!()
      # Convenience function
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

DYMO_LABEL_SIZE = [89, 36]
ZEBRA_LABEL_SIZE = [100, 60]

def render_label(item_or_label_id, size: DYMO_LABEL_SIZE)
  item = api("items/#{item_or_label_id}")

  pdf = Prawn::Document.new(page_size: size.map { |x| mm2pt(x) },
                            margin: [2, 2, 2, 6].map { |x| mm2pt(x) }) do
    font_families.update("DejaVuSans" => {
      normal: "fonts/DejaVuSans.ttf",
      italic: "fonts/DejaVuSans-Oblique.ttf",
      bold: "fonts/DejaVuSans-Bold.ttf",
      bold_italic: "fonts/DejaVuSans-BoldOblique.ttf"
    })

    font 'DejaVuSans'

    # Width of right side
    qr_size = [bounds.height / 2, 27].max

    # Right side
    bounding_box([bounds.right - qr_size, bounds.top], width: qr_size) do
      print_qr_code CODE_PREFIX + item['short_id'], stroke: false,
        foreground_color: '000000',
        extent: bounds.width, margin: 0, pos: bounds.top_left

      owner_text = item["owner"] ? "owner: #{item['owner']}\n\n" : ""
      metadata_text = owner_text # todo: creation date?

      text_box metadata_text,
        at: [bounds.right - qr_size, -7], size: 8, align: :right, overflow: :shrink_to_fit
    end

    # Left side
    bounding_box(bounds.top_left, width: bounds.width - qr_size) do
      text_box item['name'],
        size: 40, align: :center, valign: :center, width: bounds.width-10,
        inline_format: true, overflow: :shrink_to_fit, disable_wrap_by_char: true
    end
  end

  pdf.render
end

set :bind, '0.0.0.0'

get '/api/1/preview/:id.pdf' do
  headers["Content-Type"] = "application/pdf; charset=utf8"
  render_label params["id"]
end

get '/api/1/preview/:id.png' do
  headers["Content-Type"] = "image/png"
  img = Magick::ImageList.new()
  img = img.from_blob(render_label(params["id"])){ self.density = 200 }.first
  img.format = 'png'
  img.background_color = 'white'
  img.to_blob
end

post '/api/1/print/:id' do
  temp = Tempfile.new('labelmaker')
  temp.write(render_label(params["id"]))
  temp.close
  system("lpr -P DYMO_LabelWriter_450 #{temp.path}")
end

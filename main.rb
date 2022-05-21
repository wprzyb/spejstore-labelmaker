require 'rubygems'
require 'sinatra'
require 'rqrcode'
require 'prawn'
require 'prawn/measurements'
require 'prawn/qrcode'
require 'prawn-svg'
require 'color'
require 'excon'
require 'rest-client'
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

module RestClient
  class Response
    def json!()
      # Convenience function
      JSON.parse(body)
    end
  end
end

BACKEND_URL = 'http://inventory.lokal.hswro.org/api/1/'
CODE_PREFIX = "HTTP://I/"
WIKI_PREFIX = "http://wiki.hswro.org/"

$templates = {
  "prywatne" => { "name" => "Ten przedmiot jest własnością prywatną", "image" => "assets/person.svg"},
  "hsowe" => { "name" => "Ten przedmiot należy do HSWro", "image" => "assets/hswro.svg"},
  "hackuj" => { "name" => "Hackuj ile dusza zapragnie", "image" => "assets/glider.svg"},
  "zepsute" => { "name" => "Ten przedmiot jest zepsuty", "image" => "assets/dead.svg"},
  "eksploatuje" => { "name" => "Ten przedmiot eksploatuje materiały", "image" => "assets/money.svg"},
  "niehackuj" => { "name" => "Nie hackuj tego przedmiotu", "image" => "assets/glider.svg"},
  "blaty" => { "name" => "Utrzymuj czystość na blatach", "image" => "assets/clean.svg"},

# meme
  "bhp" => { "name" => "Gdy ci smutno, gdy ci źle, użyj pasty BHP", "image" => "assets/hswro.svg"},

}

def api(uri)
  RestClient.get(BACKEND_URL + uri + ".json", :debug => true).json!
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
ZEBRA_LABEL_SIZE = [50, 30]

NORMAL_LABEL_MARGIN = [2, 2, 2, 6]
DRAWER_LABEL_MARGIN = [15, 2, 2, 3]

IS_DRAWER = false

def get_item_from_api(item)
  return api("items/#{item}")
end

def prepare_normal_label(item)
  result = item
  result['qr'] = CODE_PREFIX + item['short_id']
  return result
end

def prepare_custom_hs(text)
  return {"name" => text, "image" => "assets/hswro.svg"}
end

def prepare_custom_item(name, owner)
  return {"name" => name, "owner" => owner}
end

def prepare_templated(template)
  return $templates[template] 
end

def prepare_gifted(item)
  donor = item['props']['donor'] ? item['props']['donor'] : ""
  result = {"name" => "Przedmiot podarował: #{donor}", "image" => "assets/gift.svg"}  
  return result
end

def prepare_wiki(item)
  wikiaddr = item['props']['wiki'] ? WIKI_PREFIX + item['props']['wiki'] : ""
  result = {"name" => "Wiki: #{item['props']['wiki']}", "qr" => wikiaddr}  
  return result
end




def render_label(item, size: ZEBRA_LABEL_SIZE)
  labelmargin = IS_DRAWER ? DRAWER_LABEL_MARGIN : NORMAL_LABEL_MARGIN

  pdf = Prawn::Document.new(page_size: size.map { |x| mm2pt(x) },
                            margin: labelmargin.map { |x| mm2pt(x) }) do
    font_families.update("DejaVuSans" => {
      normal: "fonts/DejaVuSans.ttf",
      italic: "fonts/DejaVuSans-Oblique.ttf",
      bold: "fonts/DejaVuSans-Bold.ttf",
      bold_italic: "fonts/DejaVuSans-BoldOblique.ttf"
    })

    font 'DejaVuSans'



    # Width of right side
#    qr_size = [bounds.height / 2, 27].max
    qr_size = [bounds.height / 2, 27].max
    image_size = [bounds.height / 2, 27].max

    # Right side
#    bounding_box([bounds.right - qr_size, bounds.top], width: qr_size) do
    bounding_box([bounds.right - qr_size, bounds.top], width: qr_size) do


      if item['qr']
	print_qr_code item['qr'], stroke: false,
          foreground_color: '000000',
          extent: bounds.width, margin: 0, pos: bounds.top_left
      end

      if item['image']
        svg IO.read(item['image']), width: image_size, position: :right
      end

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

#####################################################

get '/api/1/preview/:id.pdf' do
  headers["Content-Type"] = "application/pdf; charset=utf8"
  render_label(prepare_normal_label(get_item_from_api(params["id"])))
end

get '/api/1/preview/:id/gift.pdf' do
  headers["Content-Type"] = "application/pdf; charset=utf8"
  render_label(prepare_gifted(get_item_from_api(params["id"])))
end

get '/api/1/preview/:id/wiki.pdf' do
  headers["Content-Type"] = "application/pdf; charset=utf8"
  render_label(prepare_wiki(get_item_from_api(params["id"])))
end

get '/api/1/preview/:id.png' do
  headers["Content-Type"] = "image/png"
  img = Magick::ImageList.new()
  img = img.from_blob(render_label(prepare_normal_label(get_item_from_api(params["id"])))){ self.density = 200 }.first
  img.format = 'png'
  img.background_color = 'white'
  img.to_blob
end

post '/api/1/print/:id' do
  temp = Tempfile.new('labelmaker')
  temp.write(render_label(prepare_normal_label(get_item_from_api(params["id"]))))
  temp.close
  system("lpr -P Zebra #{temp.path}")
end

post '/api/1/print/:id/wiki' do
  temp = Tempfile.new('labelmaker')
  temp.write(render_label(prepare_wiki(get_item_from_api(params["id"]))))
  temp.close
  system("lpr -P Zebra #{temp.path}")
end

get '/api/1/test/:id' do
  get_item_from_api(params["id"])
  prepare_wiki(get_item_from_api(params["id"]))
end

#####################################################

get '/api/1/list/templates' do
  headers["Content-Type"] = "application/json"
  $templates.to_json
end

get '/api/1/preview/templates/:id' do
  headers["Content-Type"] = "application/pdf; charset=utf8"
  render_label(prepare_templated(params['id']))
end

get '/api/1/templates/preview/:id' do
  headers["Content-Type"] = "application/pdf; charset=utf8"
  render_label(prepare_templated(params['id']))
end

get '/api/1/templates/print/:id' do
  temp = Tempfile.new('labelmaker')
  temp.write(render_label(prepare_templated(params['id'])))
  temp.close
  system("lpr -P Zebra #{temp.path}")
end

get '/api/1/nametag/preview/:id' do
  headers["Content-Type"] = "application/pdf; charset=utf8"
  render_label(prepare_custom_hs(params['id']))
end

get '/api/1/nametag/print/:id' do
  temp = Tempfile.new('labelmaker')
  temp.write(render_label(prepare_custom_hs(params['id'])))
  temp.close
  system("lpr -P Zebra #{temp.path}")
end

get '/api/1/customitem/preview/:owner/:name' do
  headers["Content-Type"] = "application/pdf; charset=utf8"
  render_label(prepare_custom_item(params["name"],params["owner"]))
end

get '/api/1/customitem/print/:owner/:name' do
  temp = Tempfile.new('labelmaker')
  temp.write(render_label(prepare_custom_item(params["name"],params["owner"])))
  temp.close
  system("lpr -P Zebra #{temp.path}")
end

get '/api/1/gift/preview' do
  test = {"name" => "Przedmiot podarował: lynx, małpa, franek", "image" => "assets/gift.svg"}
  headers["Content-Type"] = "application/pdf; charset=utf8"
  render_label(false,"img",test)
end

get '/api/1/testgift/print' do
  test = {"name" => "Przedmiot podarował: lynx, małpa, franek", "image" => "assets/gift.svg"}
  temp = Tempfile.new('labelmaker')
  temp.write(render_label(false, "img",test))
  temp.close
  system("lpr -P Zebra #{temp.path}")
end



# TESTY

get '/api/1/dupatest/preview' do
  test = {"owner" => "test", "short_id" => "test", "name" => "test", "image" => "assets/glider.svg"}
  headers["Content-Type"] = "application/pdf; charset=utf8"
  render_label(false,"img",test)
end

get '/api/1/testgift/preview' do
  test = {"name" => "Przedmiot podarował: lynx, małpa, franek", "image" => "assets/gift.svg"}
  headers["Content-Type"] = "application/pdf; charset=utf8"
  render_label(false,"img",test)
end

get '/api/1/testgift/print' do
  test = {"name" => "Przedmiot podarował: lynx, małpa, franek", "image" => "assets/gift.svg"}
  temp = Tempfile.new('labelmaker')
  temp.write(render_label(false, "img",test))
  temp.close
  system("lpr -P Zebra #{temp.path}")
end

get '/api/1/testshow' do
  test = {"owner" => "grzegorz_brzęczyszczykiewicz", "short_id" => "wszczebrzeszyniechrzaszczbrzmiwtrzcinie", "name" => "pchnąć w tę łódź jeża lub ośm skrzyń fig"}
  headers["Content-Type"] = "application/pdf; charset=utf8"
  render_label(false, "qr", test)
end

get '/api/1/testprint' do
  test = {"owner" => "grzegorz_brzęczyszczykiewicz", "short_id" => "wszczebrzeszyniechrzaszczbrzmiwtrzcinie", "name" => "pchnąć w tę łódź jeża lub ośm skrzyń fig"}
  temp = Tempfile.new('labelmaker')
  temp.write(render_label(false,"qr",test))
  temp.close
  system("lpr -P Zebra #{temp.path}")
end

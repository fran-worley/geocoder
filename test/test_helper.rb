# encoding: utf-8
require 'rubygems'
require 'test/unit'

$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))

require 'yaml'
configs = YAML.load_file('test/database.yml')
ENV['ORM'] ||= 'active_record'

if configs.keys.include? ENV['DB']
  db_name = ENV['DB']

  if db_name == 'sqlite' && ENV['USE_SQLITE_EXT'] == '1' then
    gem 'sqlite_ext'
    require 'sqlite_ext'
    SqliteExt.register_ruby_math
  end

  if ENV['ORM'] == 'active_record'
    require 'active_record'

    # Establish a database connection
    ActiveRecord::Base.configurations = configs
    ActiveRecord::Base.establish_connection(db_name.to_sym)
    ActiveRecord::Base.default_timezone = :utc

    ActiveRecord::Migrator.migrate('test/db/migrate', nil)
  elsif ENV['ORM'] == 'sequel'
    require 'sequel'
    require 'geocoder/models/sequel'
    require 'geocoder/stores/sequel'
    if db_name == 'sqlite'
      configs[ENV['DB']]['adapter'] = 'sqlite' # not sqlite3
    end

    DB = Sequel.connect(configs[ENV['DB']])

    Sequel.extension(:migration)
    Sequel::Migrator.run(DB, "test/db/migrate/sequel")
  end
else
  class MysqlConnection
    def adapter_name
      "mysql"
    end
  end

  ##
  # Simulate enough of ActiveRecord::Base that objects can be used for testing.
  #
  module ActiveRecord
    class Base

      def initialize
        @attributes = {}
      end

      def read_attribute(attr_name)
        @attributes[attr_name.to_sym]
      end

      def write_attribute(attr_name, value)
        @attributes[attr_name.to_sym] = value
      end

      def update_attribute(attr_name, value)
        write_attribute(attr_name.to_sym, value)
      end

      def self.scope(*args); end

      def self.connection
        MysqlConnection.new
      end

      def method_missing(name, *args, &block)
        if name.to_s[-1..-1] == "="
          write_attribute name.to_s[0...-1], *args
        else
          read_attribute name
        end
      end

      class << self
        def table_name
          'test_table_name'
        end

        def primary_key
          :id
        end

        def maximum(_field)
          1.0
        end
      end
    end
  end
end

# simulate Rails module so Railtie gets loaded
module Rails
end

# Require Geocoder after ActiveRecord simulator.
require 'geocoder'
require 'geocoder/lookups/base'

# and initialize Railtie manually (since Rails::Railtie doesn't exist)
Geocoder::Railtie.insert

##
# Mock HTTP request to geocoding service.
#
module Geocoder
  module Lookup
    class Base
      private
      def fixture_exists?(filename)
        File.exist?(File.join("test", "fixtures", filename))
      end

      def read_fixture(file)
        filepath = File.join("test", "fixtures", file)
        s = File.read(filepath).strip.gsub(/\n\s*/, "")
        MockHttpResponse.new(body: s, code: "200")
      end

      ##
      # Fixture to use if none match the given query.
      #
      def default_fixture_filename
        "#{fixture_prefix}_madison_square_garden"
      end

      def fixture_prefix
        handle
      end

      def fixture_for_query(query)
        label = query.reverse_geocode? ? "reverse" : query.text.gsub(/[ \.]/, "_")
        filename = "#{fixture_prefix}_#{label}"
        fixture_exists?(filename) ? filename : default_fixture_filename
      end

      # This alias allows us to use this method in further tests
      # to actually test http requests
      alias_method :actual_make_api_request, :make_api_request
      remove_method(:make_api_request)

      def make_api_request(query)
        raise Timeout::Error if query.text == "timeout"
        raise SocketError if query.text == "socket_error"
        raise Errno::ECONNREFUSED if query.text == "connection_refused"
        raise Errno::EHOSTUNREACH if query.text == "host_unreachable"
        if query.text == "invalid_json"
          return MockHttpResponse.new(:body => 'invalid json', :code => 200)
        end

        read_fixture fixture_for_query(query)
      end
    end

    require 'geocoder/lookups/bing'
    class Bing
      private
      def read_fixture(file)
        if file == "bing_service_unavailable"
          filepath = File.join("test", "fixtures", file)
          s = File.read(filepath).strip.gsub(/\n\s*/, "")
          MockHttpResponse.new(body: s, code: "200", headers: {'x-ms-bm-ws-info' => "1"})
        else
          super
        end
      end
    end

    require 'geocoder/lookups/google_premier'
    class GooglePremier
      private
      def fixture_prefix
        "google"
      end
    end

    require 'geocoder/lookups/google_places_details'
    class GooglePlacesDetails
      private
      def fixture_prefix
        "google_places_details"
      end
    end

    require 'geocoder/lookups/dstk'
    class Dstk
      private
      def fixture_prefix
        "google"
      end
    end

    require 'geocoder/lookups/location_iq'
    class LocationIq
      private
      def fixture_prefix
        "location_iq"
      end
    end

    require 'geocoder/lookups/yandex'
    class Yandex
      private
      def default_fixture_filename
        "yandex_kremlin"
      end
    end

    require 'geocoder/lookups/freegeoip'
    class Freegeoip
      private
      def default_fixture_filename
        "freegeoip_74_200_247_59"
      end
    end

    require 'geocoder/lookups/geoip2'
    class Geoip2
      private

      remove_method(:results)

      def results(query)
        return [] if query.to_s == 'no results'
        return [] if query.to_s == '127.0.0.1'
        [{'city'=>{'names'=>{'en'=>'Mountain View', 'ru'=>'Маунтин-Вью'}},'country'=>{'iso_code'=>'US','names'=>
        {'en'=>'United States'}},'location'=>{'latitude'=>37.41919999999999,
        'longitude'=>-122.0574},'postal'=>{'code'=>'94043'},'subdivisions'=>[{
        'iso_code'=>'CA','names'=>{'en'=>'California'}}]}]
      end

      def default_fixture_filename
        'geoip2_74_200_247_59'
      end
    end

    require 'geocoder/lookups/telize'
    class Telize
      private
      def default_fixture_filename
        "telize_74_200_247_59"
      end
    end

    require 'geocoder/lookups/pointpin'
    class Pointpin
      private
      def default_fixture_filename
        "pointpin_80_111_55_55"
      end
    end

    require 'geocoder/lookups/maxmind'
    class Maxmind
      private
      def default_fixture_filename
        "maxmind_74_200_247_59"
      end
    end

    require 'geocoder/lookups/maxmind_geoip2'
    class MaxmindGeoip2
      private
      def default_fixture_filename
        "maxmind_geoip2_1_2_3_4"
      end
    end

    require 'geocoder/lookups/maxmind_local'
    class MaxmindLocal
      private

      remove_method(:results)

      def results query
        return [] if query.to_s == "no results"

        if query.to_s == '127.0.0.1'
          []
        else
          [{:request=>"8.8.8.8", :ip=>"8.8.8.8", :country_code2=>"US", :country_code3=>"USA", :country_name=>"United States", :continent_code=>"NA", :region_name=>"CA", :city_name=>"Mountain View", :postal_code=>"94043", :latitude=>37.41919999999999, :longitude=>-122.0574, :dma_code=>807, :area_code=>650, :timezone=>"America/Los_Angeles"}]
        end
      end
    end

    require 'geocoder/lookups/baidu'
    class Baidu
      private
      def default_fixture_filename
        "baidu_shanghai_pearl_tower"
      end
    end

    require 'geocoder/lookups/baidu_ip'
    class BaiduIp
      private
      def default_fixture_filename
        "baidu_ip_202_198_16_3"
      end
    end

    require 'geocoder/lookups/geocodio'
    class Geocodio
      private
      def default_fixture_filename
        "geocodio_1101_pennsylvania_ave"
      end
    end

    require 'geocoder/lookups/okf'
    class Okf
      private
      def default_fixture_filename
        "okf_kirstinmaki"
      end
    end

    require 'geocoder/lookups/postcode_anywhere_uk'
    class PostcodeAnywhereUk
      private
      def fixture_prefix
        'postcode_anywhere_uk_geocode_v2_00'
      end

      def default_fixture_filename
        "#{fixture_prefix}_romsey"
      end
    end

    require 'geocoder/lookups/geoportail_lu'
    class GeoportailLu
      private
      def fixture_prefix
        "geoportail_lu"
      end

      def default_fixture_filename
        "#{fixture_prefix}_boulevard_royal"
      end
    end

    require 'geocoder/lookups/latlon'
    class Latlon
      private
      def default_fixture_filename
        "latlon_6000_universal_blvd"
      end
    end

    require 'geocoder/lookups/mapzen'
    class Mapzen
      def fixture_prefix
        'pelias'
      end
    end

    require 'geocoder/lookups/ipinfo_io'
    class IpinfoIo
      private
      def default_fixture_filename
        "ipinfo_io_8_8_8_8"
      end
    end

    require 'geocoder/lookups/ipapi_com'
    class IpapiCom
      private
      def default_fixture_filename
        "ipapi_com_74_200_247_59"
      end
    end

    require 'geocoder/lookups/ban_data_gouv_fr'
    class BanDataGouvFr
      private
      def fixture_prefix
        "ban_data_gouv_fr"
      end

      def default_fixture_filename
        "#{fixture_prefix}_rue_yves_toudic"
      end
    end

    require 'geocoder/lookups/amap'
    class Amap
      private
      def default_fixture_filename
        "amap_shanghai_pearl_tower"
      end
    end

    require 'geocoder/lookups/pickpoint'
    class Pickpoint
      private
      def fixture_prefix
        "pickpoint"
      end
    end

  end
end


##
# Geocoded model.
#
if ENV['ORM'] == 'sequel'
  Sequel::Model.strict_param_setting = false # ignore attempts to access restricted setter methods

  require 'sequel_test_models'
else
  require 'active_record_test_models'
end

class GeocoderTestCase < Test::Unit::TestCase
  def setup
    super
    Geocoder::Configuration.instance.set_defaults
    Geocoder.configure(
      :maxmind => {:service => :city_isp_org},
      :maxmind_geoip2 => {:service => :insights, :basic_auth => {:user => "user", :password => "password"}})
  end

  def geocoded_object_params(abbrev)
    {
      :msg => ["Madison Square Garden", "4 Penn Plaza, New York, NY"]
    }[abbrev]
  end

  def reverse_geocoded_object_params(abbrev)
    {
      :msg => ["Madison Square Garden", 40.750354, -73.993371]
    }[abbrev]
  end

  def set_api_key!(lookup_name)
    lookup = Geocoder::Lookup.get(lookup_name)
    if lookup.required_api_key_parts.size == 1
      key = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    elsif lookup.required_api_key_parts.size > 1
      key = lookup.required_api_key_parts
    else
      key = nil
    end
    Geocoder.configure(:api_key => key)
  end
end

class MockHttpResponse
  attr_reader :code, :body
  def initialize(options = {})
    @code = options[:code].to_s
    @body = options[:body]
    @headers = options[:headers] || {}
  end

  def [](key)
    @headers[key]
  end
end

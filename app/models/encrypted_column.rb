require 'securerandom'
require 'base64'

class EncryptedColumn
  attr_reader :disable, :options
  alias disabled? disable

  def initialize(options = {})
    @options = options || {}
    @disable = self.options[:disable]
    @key = self.options[:key]
  end

  def enabled?
    !disabled?
  end

  def load(data)
    return nil unless data

    data = data.to_s

    decrypt?(data) ? decrypt(data) : data
  end

  def dump(data)
    encrypt?(data) ? encrypt(data.to_s) : data
  end

  def key
    @key || config["encryption"]["key"]
  end

  def iv
    SecureRandom.hex(8)
  end

  def prefix
    '--ENCR--'
  end

  def decrypt?(data)
    data.present? && (!use_prefix? || prefix_used?(data))
  end

  def encrypt?(data)
    data.present? && enabled?
  end

  def prefix_used?(data)
    data[0..7] == prefix
  end

  def decrypt(data)
    data = data[8..-1] if prefix_used?(data)

    data = decode data

    iv   = data[-16..-1]
    data = data[0..-17]

    aes = create_aes :decrypt, key.to_s, iv

    result = aes.update(data) + aes.final
    if result
      result.force_encoding('UTF-8')
    end
  end

  def encrypt(data)
    iv = self.iv

    aes = create_aes :encrypt, key.to_s, iv

    encrypted = aes.update(data) + aes.final

    encrypted = "#{encrypted}#{iv}"
    encrypted = encode encrypted
    encrypted = "#{prefix}#{encrypted}" if use_prefix?
    encrypted
  end

  def use_prefix?
    options.has_key?(:use_prefix)
  end

  def create_aes(mode = :encrypt, key, iv)
    aes = OpenSSL::Cipher::AES.new(256, :CBC)

    aes.send(mode)
    aes.key = key[0..31]
    aes.iv  = iv

    aes
  end

  def config
    file = File.expand_path('config/travis.yml')
    env = ENV['RAILS_ENV']
    YAML.load_file(file)[env]
  end

  def decode(str)
    Base64.strict_decode64 str
  end

  def encode(str)
    Base64.strict_encode64 str
  end
end

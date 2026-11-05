# frozen_string_literal: true

require "base64"

module Haskimail
  # An email attachment in the API format.
  #
  #   Haskimail::Attachment.from_file("invoice.pdf")
  #   # Inline image, referenced in HTML as <img src="cid:logo.png">
  #   Haskimail::Attachment.new(name: "logo.png", content: png_bytes, content_type: "image/png",
  #                             content_id: "logo.png")
  #
  # The Content-ID is sent bare: Haskimail uses ContentID verbatim as the MIME
  # Content-ID, so "cid:" prefixes and angle brackets are stripped.
  class Attachment
    # Extensions rejected by Haskimail (https://haskimail.ru/developer/user-guide/send-email-with-api).
    FORBIDDEN_EXTENSIONS = %w[
      vbs exe bin bat chm com cpl crt hlp hta inf ins isp jse lnk mdb pcd pif reg scr sct shs
      vbe vba wsf wsh wsl msc msi msp mst
    ].freeze

    DEFAULT_CONTENT_TYPE = "application/octet-stream"

    attr_reader :name, :content_type, :content_id

    # @param content [String] raw (not Base64-encoded) bytes
    def initialize(name:, content:, content_type: nil, content_id: nil)
      @name = name.to_s
      raise ArgumentError, "Attachment name is required" if @name.strip.empty?

      self.class.assert_allowed!(@name)
      @content = content.to_s.b
      @content_type = content_type || self.class.guess_content_type(@name)
      @content_id = self.class.normalize_content_id(content_id)
    end

    # "cid:logo.png" / "<logo.png>" -> "logo.png"; blank -> nil.
    def self.normalize_content_id(value)
      id = value.to_s.strip.delete_prefix("<").delete_suffix(">").sub(/\Acid:/i, "").strip
      id = id.delete_prefix("<").delete_suffix(">").strip
      return nil if id.empty?
      raise ArgumentError, "Invalid ContentID #{value.inspect}" if id.match?(/[\s<>"\0]/)

      id
    end

    def self.from_file(path, name: nil, content_type: nil, content_id: nil)
      new(name: name || File.basename(path.to_s), content: File.binread(path),
          content_type: content_type, content_id: content_id)
    end

    def self.assert_allowed!(filename)
      extension = File.extname(filename.to_s).delete_prefix(".").downcase
      return unless FORBIDDEN_EXTENSIONS.include?(extension)

      raise ArgumentError, "Attachments with .#{extension} extension are rejected by Haskimail"
    end

    def self.guess_content_type(filename)
      require "mini_mime"
      MiniMime.lookup_by_filename(filename.to_s)&.content_type || DEFAULT_CONTENT_TYPE
    rescue LoadError
      DEFAULT_CONTENT_TYPE
    end

    def bytesize
      @content.bytesize
    end

    def to_h
      Util.compact(
        "Name" => name,
        "Content" => Base64.strict_encode64(@content),
        "ContentType" => content_type,
        "ContentID" => content_id
      )
    end
    alias to_api to_h

    def inspect
      "#<#{self.class.name} name=#{name.inspect} content_type=#{content_type.inspect} bytes=#{bytesize}>"
    end
  end
end

# encoding: utf-8
require 'tempfile'
require 'tsort'
require 'set'
require 'rubygems'
require 'nokogiri'
require 'kramdown'
require 'chronic'
require 'haml'

class Pigeon
  attr :actions
  def initialize(actions)
    @actions = actions
  end
  def dependencies action, &block
    @actions.each do |other|
      if action[:requires].include? other[:provide]
        block.call other
      end
    end
  end
  def execute start
    # TODO: erase attributes once they're no longer needed
    # TODO: finalizers for attributes
    self.tsort.each do |action|
      arguments = action[:requires].map { |r| start[r] }
      provided  = action[:block].call *arguments
      if action[:provide]
        start[action[:provide]] = provided
      end
    end
    return start
  end
  # List all of the attributes that are not provided within.
  def free
    set = Set.new []
    @actions.each { |a| set.merge(a[:requires]) }
    set.subtract @actions.map { |a| a[:provide] }
    return set.to_a
  end
  include TSort
  def tsort_each_node &block
    @actions.each &block
  end
  alias tsort_each_child dependencies
end

module Pigeon::Action
  Markdown = {
    :requires => [:source],
    :provide  => :html,
    :block    => lambda do |source|
      md = Kramdown::Document.new (File.read source),
        :coderay_line_numbers => nil,
        :coderay_css => :class
      file = Tempfile.new source
      file.write md.to_html
      file.rewind
      return file
    end
  }

  # Parse HTML with nokogiri
  ParseHtml = {
    :requires => [:html],
    :provide  => :document,
    :block    => lambda do |html|
      document = Nokogiri::HTML html, nil, "utf-8"
      html.rewind
      return document
    end
  }

  # Stick the title in.
  GetTitle = {
    :requires => [:document],
    :provide  => :title,
    :block    => lambda do |document|
      h1s = document.css('h1')
      if h1s.length > 0
        return h1s[0].text
      else
        return nil
      end
    end
  }
  
  # Stick the date in.
  GetDate = {
    :requires => [:document],
    :provide  => :date,
    :block    => lambda do |document|
      times = document.css 'time[pubdate]'
      if times.length > 0
        return Chronic.parse times[0]["datetime"]
      else
        return nil
      end
    end
  }
  
  # Render each thing with a template.
  Template = {
    :requires => [:title, :date, :html, :options],
    :provide  => :output,
    :block    => lambda do |title, date, html, options|
      page = Haml::Engine.new <<-END.gsub(/^ {8}/, '')
        !!! 5
        %html
          %head
            %meta{ :charset => "utf-8" }
            - if options.stylesheet
              %link{ :rel   => "stylesheet",
                     :type  => "text/css",
                     :media => "screen",
                     :href  => options.stylesheet }
            %title
              = options.title
          %body
            %article
              ~ html.read
        END
      return page.render Object.new,
        :title   => title,
        :date    => date,
        :html    => html,
        :options => options
    end
  }
  
  # Deduce the filename for each article.
  Filename = {
    :requires => [:title, :date],
    :provide  => :filename,
    :block    => lambda do |title, date|
      pretty = date.strftime "%Y-%m-%d"
      return "#{pretty}-#{title}.html" 
    end
  }
  
  # Create an action writing :output to :filename.
  WriteOut = {
    :requires => [:output, :filename, :options],
    :provide  => nil,
    :block    => lambda do |output, filename, options|
      f = File.open File.join(options[:output], filename), "w"
      f.write output
      f.close
    end
  }
end

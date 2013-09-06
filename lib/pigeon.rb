# encoding: utf-8
require 'tsort'
require 'set'
require 'rubygems'
require 'nokogiri'
require 'kramdown'
require 'chronic'
require 'haml'

# This library introduces a notion of `actions' that produce values
# labeled with symbols and that may depend on other actions. For now,
# these are represented as hashes with at least three keys: `:requires',
# `:provide', and `:block'. The last of these must be any thing that may
# be called with a number of parameters corresponding to the list in
# `:requires'.
#
# A 'Pigeon' object, then, is just a collection of these actions. They
# may be topologically sorted and executed in order.
#
# Further niceties such as symbol capture, composition of 'Pigeon's,
# and pruning of unnecessary metadata are forthcoming.
class Pigeon
  def initialize(actions)
    @actions = actions
  end

  # Fold over the actions which an action will require.
  def dependencies action, &block
    @actions.each do |other|
      if action[:requires].include? other[:provide]
        block.call other
      end
    end
  end

  # Given a hash of initial attributes, run each action in
  # dependency-wise topological order.
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
  def fr
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
  # Transform the markdown source (under ':source') into
  # soqme HTML.
  Markdown = {
    :requires => [:source],
    :provide  => :html,
    :block    => lambda do |source|
      md = Kramdown::Document.new (File.read source),
        :coderay_line_numbers => nil,
        :coderay_css => :class
      return md.to_html
    end
  }

  # Parse HTML (under ':html') with nokogiri into ':document'.
  ParseHtml = {
    :requires => [:html],
    :provide  => :document,
    :block    => lambda do |html|
      return Nokogiri::HTML html
    end
  }

  # Create a title.
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
  
  # Parse a date.
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
  
  # Render with a baked-in template.
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
              ~ html
        END
      return page.render Object.new,
        :title   => title,
        :date    => date,
        :html    => html,
        :options => options
    end
  }
  
  # Deduce a filename.
  Filename = {
    :requires => [:title],
    :provide  => :filename,
    :block    => lambda do |title|
      # TODO: make this URI-safe
      "#{title}.html".tr " ", "-"
    end
  }
  
  # Write ':output' to ':filename'.
  WriteOut = {
    :requires => [:output, :filename, :options],
    :provide  => nil,
    :block    => lambda do |output, filename, options|
      target = File.join options[:output], filename
      open(target, "w") { |f| f.write output }
    end
  }
end

# encoding: utf-8
require 'tempfile'
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
  def register(requires, provide, &block)
    @actions.push ({
      :requires => requires,
      :provide => provide,
      :block => block
    })
    return self
  end
  def execute start
    # TODO: do this in topological order
    # TODO: erase attributes once they're no longer needed
    # TODO: finalizers for attributes
    @actions.each do |action|
      action[:block].call start
    end
    return start
  end
  # List all of the attributes that are not provided within.
  def free
    set = Set.new []
    @actions.each { |a| set.merge(a[:requires]) }
    set.subtract (@actions.map { |a| a[:provide] })
    return set.to_a
  end
end

main = Pigeon.new []

# Read markdown into html.
main.register([:source], :html) do |article|
  md = Kramdown::Document.new(File.read(article[:source]))
  file = Tempfile.new article[:source]
  file.write md.to_html
  file.rewind
  article[:html] = file
end

# Parse HTML with nokogiri
main.register([:html], :document) do |article|
  article[:document] = Nokogiri::HTML(article[:html], nil, "utf-8")
  article[:html].rewind
end

# Stick the title in.
main.register([:document], :title) do |article|
  h1s = article[:document].css('h1')
  if h1s.length > 0
    article[:title] = h1s[0].text
  else
    article[:title] = nil
  end
end

# Stick the date in.
main.register([:document], :date) do |article|
  times = article[:document].css('time[pubdate]')
  if times.length > 0
    article[:date] = Chronic.parse times[0]["datetime"]
  else
    article[:date] = nil
  end
end

# Render each thing with a template.
main.register([:title, :date, :html], :output) do |article|
  template = Haml::Engine.new <<-END.gsub(/^ {4}/, '')
    !!! 5
    %html
      %head
        %meta{ :charset => "utf-8" }
        %title
          = title
      %body
        %article
          = html.read
    END
  article[:output] = template.render(Object.new, article)
end

# Deduce the filename for each article.
main.register([:title, :date], :filename) do |article|
  pretty = article[:date].strftime("%Y-%m-%d")
  article[:filename] = "#{pretty}-#{article[:title]}.html" 
end

# Blah
source, destination = ARGV
source ||= "."
destination ||= source
articles = Dir.glob("#{source}/*.markdown")
  .map { |a| main.execute(:source => a) }
articles.each do |article|
  f = File.open("#{destination}/#{article[:filename]}", "w")
  f.write article[:output]
  f.close
end

index = Haml::Engine.new <<-END.gsub(/^ {2}/, '')
  !!! 5
  %html
    %head
      %meta{ :charset => "utf-8" }
      %title
        startlelog
    %body
      %h1 Blog Posts
      %ul.articles
        - articles.each do |ar|
          %li
            - if ar[:date]
              %time{ :datetime => ar[:date] }
                = ar[:date].strftime("%-d %b %y")
            - else
              %time.unknown
            &mdash;
            - if ar[:title]
              %a.article{ :href => ar[:filename] }
                = ar[:title]
            - else
              %a.article.empty{ :href => ar[:filename] }
  END
f = File.open("#{destination}/index.html", "w")
f.write(index.render(Object.new, :articles => articles))
f.close


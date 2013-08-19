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
  def execute(objects)
    # TODO: do this in topological order
    # TODO: erase attributes once they're no longer needed
    # TODO: finalizers for attributes
    objects.each do |obj|
      @actions.each do |action|
        action[:block].call obj
      end
    end
  end
  # List all of the attributes that are not provided within.
  def free()
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
  article[:document] = Nokogiri::HTML(article[:html])
  article[:html].rewind
end

# Stick the title in.
main.register([:document], :title) do |article|
  article[:title] = article[:document].css('h1')[0].text
end

# Stick the date in.
main.register([:document], :date) do |article|
  date = article[:document].css('time[pubdate]')[0]["datetime"]
  article[:date] = Chronic.parse date
end

main.register([:title, :date, :html], :output) do |article|
  template = Haml::Engine.new <<-END.gsub(/^ {4}/, '')
    !!! 5
    %html
      %head
        %title
          = title
      %body
        %article
          = html.read
    END
  article[:output] = template.render(Object.new, article)
end

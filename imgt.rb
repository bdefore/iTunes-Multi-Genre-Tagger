# iTunes Multi-Genre Tagger
# http://bcdef.org/itunes-multi-genre-tagger/
#
# iTunes Multi-Genre Tagger adds descriptive metadata to your music. These descriptive tags 
# are gathered from the Last.FM API (no user account necessary) and then written into the
# ‘Grouping’ field of your music file(s).
#
# And wherefore? To break old habits. With the ‘Grouping’ column displayed in iTunes, this
# enables you to filter music by multiple categories, even very specific ones (i.e. “90s 
# argentina indie”) from within the iTunes search feature. In this way you’ll find music
# you’d otherwise not think to listen to.
#
# Dependencies: libxml, rb-appscript (gem install rb-appscript)
#
# Author:
# Buck DeFore 
# https://github.com/bdefore
#
# Extended from Last.FM Music Tagger by wes@633k.net

puts "Starting iTunes Multi-Genre Tagger...\n\n"

begin require 'rubygems'; rescue LoadError; end

# TODO:
# Package gems into portable Pashua app. gem.use_paths not behaving
#
# Currently not working:
#
#gem_path = File.dirname(__FILE__) + "/gems/"
#Gem.use_paths(nil, [ gem_path ])
#Gem.refresh

require 'appscript'

%W{rbosa net/http cgi rexml/document artist tagger color}.map { |i| begin require i; rescue LoadError; end }

$:.push(File.dirname($0))

require 'Pashua'
include Pashua

PashuaConfig = <<EOS
# Set transparency: 0 is transparent, 1 is opaque
*.transparency=0.95
*.x=20
*.y=40

# Set window title
*.title = iTunes Multi-Genre Tagger

# Introductory text
txt.type = text
txt.default = iTunes Multi-Genre Tagger adds descriptive metadata to your music. These descriptive tags are gathered from the Last.FM API (no user account necessary) and then written into the 'Grouping' field of your music file(s).
txt.width = 360

# Introductory text
txt2.type = text
txt2.default = And wherefore? To break old habits. With the 'Grouping' column displayed in iTunes, this enables you to filter music by multiple categories, even very specific ones (i.e. "90s argentina indie") from within its search feature. In this way you'll find music you'd otherwise not think to listen to.
txt2.width = 360

txt4.type = text
txt4.default = To write the tags to your files, select any number of songs in iTunes and hit 'Get Tags!' at the bottom of this window.
txt4.width = 360

# Introductory text
txt3.type = text
txt3.default = NOTE: The 'Grouping' field is typically unused and therefore empty, but be sure nothing important is in this field for the selected songs before running. If anything is in the field it will be overwritten.
txt3.width = 360

# Add a text field
minscrobs.type = textfield
minscrobs.label = Minimum popularity of tag (Integer)
minscrobs.default = 5
minscrobs.width = 60

# Add a text field
maxtags.type = textfield
maxtags.label = Maximum tags to save (Integer)
maxtags.default = 20
maxtags.width = 60

# Add a cancel button with default label
cb.type = cancelbutton

db.type = defaultbutton
db.label = Get Tags!

EOS

class Artist
  attr_reader :name, :genre
  
  def initialize(name='', genre='')
    @name, @genre = name, genre
    query unless name == ''
  end
  
  def query
    if GENRES.include?(@name)
      @genre = GENRES[@name]
      puts %{"#{@name}" found in local database, skipping last.fm query...}
    else
      puts %{Querying last.fm for: "#{@name}"...}
      begin
        doc = REXML::Document.new(Net::HTTP.get(URI("http://ws.audioscrobbler.com/1.0/artist/#{URI.escape(CGI.escape(@name))}/toptags.xml")))
      rescue EOFError => e
        puts "#{Color.error} Request timed out! Trying again..."
        query
      rescue Exception
        puts "Unknown error"
      end
      if doc
        @genre = '';
        arrNames = REXML::XPath.match(doc, "//toptags/tag/name")
        arrCounts = REXML::XPath.match(doc, "//toptags/tag/count")
        totalTags = arrNames.length
        if totalTags > MAXTAGS
          totalTags = MAXTAGS
        end
        counter = 0
        totalTags.times do 
          name = arrNames[counter]
          @genre += Integer(arrCounts[counter].text.strip) > MINSCROBS ? name.text.strip + " " : ""
          counter = counter+1
        end
      end
    end
    
    GENRES[@name] = @genre unless GENRES.include?(@name)
  end
end

class Color
  def self.pass
#    "[ \e[33mPASS\e[0m ]"
    "[ SKIP ]"
  end
  
  def self.success
#    "[ \e[32mSUCCESS\e[0m ]"
    "[ SUCCESS ]"

  end
  
  def self.error
#    "[ \e[31mERROR\e[0m ]"
    "[ ERROR ]"
   
  end
end

class Tagger
  @@tagged, @@skipped, @@indentical = 0, 0, 0

  def initialize
    itunes = Appscript.app('iTunes')
    @selection = itunes.selection
    @artist = Artist.new
#    @artists = @selection.map { |s| s.artist }.uniq.length
    @artists = @selection.artist

#    $stderr.puts "#{Color.error} Please select some tracks in iTunes" if @selection.empty?
  end

  def start
#    puts "#{@selection.length} tracks selected.\n#{@artists} unique artists."
    itunes = Appscript.app('iTunes')
    itunes.selection.get.each do |track|
      # check if artist differs; if so, reinstantiate @artist
      if @artist.name != track.artist.get
        @artist = Artist.new(track.artist.get)
        if @artist.genre == ""
          puts %{#{Color.pass} No tags found for "#{@artist.name}".}
          @@skipped += 1
          @input = 'n'
        else
          #puts "#{idx+1} out of #{@selection.length}"
          @input = confirm
        end
      end
      track.grouping.set(@artist.genre) if @input == 'y'
    end
    puts "\nDone!\n\nTags Found:\t#{@@tagged}\nSkipped:\t\t#{@@skipped}\nIdentical:\t#{@@indentical}"
  end
  
  def confirm
    print %{#{Color.success} Tagging "#{@artist.name}" as "#{@artist.genre}". }
    @@tagged += 1

    # add some space when in quiet mode
    if quiet?
      puts
      return 'y'
    end

    print %{Continue? (y/n/q) }
    gets.chomp.downcase
  end

  # handles -q argument
  def quiet?
#    return true if ARGV[0] == '-q'
    return true
  end
end

#OSA.utf8_strings = true

GENRES = {}

res = pashua_run PashuaConfig

if res['cb'] == "1"
  puts "Looks like the dialog was cancelled"
else
  MAXTAGS = Integer(res['maxtags'])
  MINSCROBS = Integer(res['minscrobs'])
  Tagger.new.start
 end
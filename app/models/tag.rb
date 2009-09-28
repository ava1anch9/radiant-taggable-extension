class Tag < ActiveRecord::Base

  attr_accessor :cloud_band, :cloud_size
  
  belongs_to :created_by, :class_name => 'User'
  belongs_to :updated_by, :class_name => 'User'
  has_many :taggings, :dependent => :destroy
  is_site_scoped if defined? ActiveRecord::SiteNotFound

  # this is useful when we need to go back and add popularity to an already defined list of tags
  
  named_scope :in_this_list, lambda { |tags|
    {
      :conditions => ["tags.id IN (#{tags.map{'?'}.join(',')})", *tags.map{|t| t.is_a?(Tag) ? t.id : t}]
    }
  }
  
  # NB unused tags are omitted
  
  named_scope :with_count, {
    :select => "tags.*, count(tt.id) AS use_count", 
    :joins => "INNER JOIN taggings as tt ON tt.tag_id = tags.id", 
    :group => "tags.id",
    :order => 'title ASC'
  }
  
  named_scope :most_popular, lambda { |count|
    {
      :select => "tags.*, count(tt.id) AS use_count", 
      :joins => "INNER JOIN taggings as tt ON tt.tag_id = tags.id", 
      :group => "tags.id",
      :limit => count,
      :order => 'use_count DESC'
    }
  }
  
  # NB. this doesn't work with a heterogeneous group. 
  named_scope :attached_to, lambda { |these|
    klass = these.first.is_a?(Page) ? Page : these.first.class
    {
      :joins => "INNER JOIN taggings ON taggings.tag_id = tags.id", 
      :conditions => ["taggings.tagged_type = '#{klass}' and taggings.tagged_id IN (#{these.map{'?'}.join(',')})", *these.map(&:id)],
    }
  }
  
  # Standardises formatting of tag name in urls
  
  def clean_title
    Rack::Utils.escape(title)
  end
  
  # Returns a list of all the objects tagged with this tag. We can't do this in SQL because it's polymorphic (and has_many_polymorphs makes my skin itch)
  
  def tagged
    taggings.map {|t| t.tagged}
  end
  
  # Returns a list of all the tags that have been applied alongside this one.
  
  def coincident_tags
    tags = []
    self.tagged.each do |t|
      tags += t.attached_tags if t
    end
    tags.uniq - [self]
  end
  
  # Returns a list of all the tags that have been applied alongside _all_ of the supplied tags.
  # used for faceting on tag pages
  
  def self.coincident_with(tags)
    related_tags = []
    tagged = Tagging.with_all_of_these(tags).map(&:tagged)
    tagged.each do |t|
      related_tags += t.attached_tags if t
    end
    related_tags.uniq - tags
  end
  
  # returns true if tags are site-scoped
  
  def self.sited?
    !reflect_on_association(:site).nil?
  end
  
  # turns a comma-separate string of tag titles into a list of tag objects, creating where necessary

  def self.from_list(list='', or_create=true)
    return [] if list.blank?
    list.split(/[,;]\s*/).uniq.map { |t| self.for(t, or_create) }
  end
  
  # finds or creates a tag with the supplied title
  
  def self.for(title, or_create=true)
    if or_create
      self.sited? ? self.find_or_create_by_title_and_site_id(title, Page.current_site.id) : self.find_or_create_by_title(title)
    else
      self.sited? ? self.find_by_title_and_site_id(title, Page.current_site.id) : self.find_by_title(title)
    end
  end
  
  # applies the usual cloud-banding algorithm to a set of tags with use_count
  
  def self.banded(tags=Tag.most_popular(100), bands=6)
    if tags
      count = tags.map{|t| t.use_count.to_i}
      if count.any? # urgh. dodging named_scope count bug
        max_use = count.max
        min_use = count.min
        divisor = ((max_use - min_use) / bands) + 1
        tags.each do |tag|
          tag.cloud_band = (tag.use_count.to_i - min_use) / divisor
        end
        tags
      end
    end
  end
  
  def self.sized(tags=Tag.most_popular(100), threshold=0, biggest=1.0, smallest=0.4)
    logger.warn "*** sized! #{tags.map(&:title)}, #{threshold}, #{biggest}, #{smallest}"
    if tags
      counts = tags.map{|t| t.use_count.to_i}
      logger.warn "*   counts #{counts.inspect}"

      if counts.any? # urgh. dodging named_scope count bug
        max = counts.max
        min = counts.min
        logger.warn "*   max = #{max}, min #{min}"
        
        steepness = Math.log(max - (min-1))/(biggest - smallest)
        logger.warn "*   steepness = Math.log(#{max} - (#{min}-1))/(#{biggest} - #{smallest})"
        logger.warn "*   steepness = #{steepness}"

        tags.each do |tag|
          offset = Math.log(tag.use_count.to_i - (min-1))/steepness
          tag.cloud_size = sprintf("%.2f", smallest + offset)
          
          logger.warn "*   #{tag.title}.cloud_size = Math.log(#{tag.use_count.to_i} - (#{min}-1))/#{steepness}) + #{smallest}"
          logger.warn ">   #{tag.title}.cloud_size = #{tag.cloud_size}"
        end
        tags
      end
    end
  end
  
  # takes a list of tags and reaquires it from the database, this time with incidence.
  
  def self.get_popularity_of(tags)
    return tags if tags.empty? || tags.first.cloud_size
    sized(in_this_list(tags).with_count)
  end
  
  # adds retrieval methods for a taggable class to this class and to Tagging.
  
  def self.define_class_retrieval_methods(classname)
    Tagging.send :named_scope, "of_#{classname.downcase.pluralize}".intern, :conditions => { :tagged_type => classname.to_s }
    define_method("#{classname.downcase}_taggings") { self.taggings.send "of_#{classname.downcase.pluralize}".intern }
    define_method("#{classname.downcase.pluralize}") { self.send("#{classname.to_s.downcase}_taggings".intern).map{|l| l.tagged} }
  end
      
end


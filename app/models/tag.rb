class Tag < ActiveRecord::Base

  attr_accessor :cloud_band
  
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
  
  # NB the inner joins mean that unused tags are omitted
  
  named_scope :with_count, {
    :select => "tags.*, count(taggings.id) AS use_count", 
    :joins => "INNER JOIN taggings ON taggings.tag_id = tags.id", 
    :group => "tags.id",
    :order => 'title ASC'
  }
  
  named_scope :most_popular, lambda { |count|
    {
      :select => "tags.*, count(taggings.id) AS use_count", 
      :joins => "INNER JOIN taggings ON taggings.tag_id = tags.id", 
      :group => "taggings.tag_id",
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
  
  def self.banded(tags=Tag.most_popular(1000), bands=6)
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
  
  # takes a list of tags and reaquires it from the database, this time with incidence.
  
  def self.get_popularity_of(tags)
    return tags if tags.empty? || tags.first.cloud_band
    banded(in_this_list(tags).with_count)
  end
  
  # adds retrieval methods for a taggable class to this class and to Tagging.
  
  def self.define_class_retrieval_methods(classname)
    Tagging.send :named_scope, "of_#{classname.downcase.pluralize}".intern, :conditions => { :tagged_type => classname.to_s }
    define_method("#{classname.downcase}_taggings") { self.taggings.send "of_#{classname.downcase.pluralize}".intern }
    define_method("#{classname.downcase.pluralize}") { self.send("#{classname.to_s.downcase}_taggings".intern).map{|l| l.tagged} }
  end
      
end


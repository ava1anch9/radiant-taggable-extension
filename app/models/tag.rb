class Tag < ActiveRecord::Base

  attr_accessor :cloud_band
  
  belongs_to :created_by, :class_name => 'User'
  belongs_to :updated_by, :class_name => 'User'
  has_many :taggings, :dependent => :destroy
  is_site_scoped if defined? ActiveRecord::SiteNotFound

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
  
  named_scope :attached_to, lambda { |these|
    klass = these.first.is_a?(Page) ? Page : these.first.class
    {
      :joins => "INNER JOIN taggings ON taggings.tag_id = tags.id", 
      :conditions => ["taggings.tagged_type = '#{klass}' and taggings.tagged_id IN (#{these.map{'?'}.join(',')})", *these.map{|p| p.id}],
    }
  }
  
  def self.sited?
    !reflect_on_association(:site).nil?
  end

  def self.from_list(list='')
    return [] if list.blank?
    list.split(/[,;]\s*/).uniq.map { |t| self.for(t) }
  end
  
  def self.for(title)
    self.sited? ? self.find_or_create_by_title_and_site_id(title, Page.current_site.id) : self.find_or_create_by_title(title)
  end
  
  def self.banded(tags, bands=6)
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
    
  def self.addTaggableMethodsTo(classname)
    Tagging.send :named_scope, "of_#{classname.downcase.pluralize}".intern, :conditions => { :tagged_type => classname.to_s }
    define_method("#{classname.downcase}_taggings") { self.taggings.send "of_#{classname.downcase.pluralize}".intern }
    define_method("#{classname.downcase.pluralize}") { self.send("#{classname.to_s.downcase}_taggings".intern).map{|l| l.tagged} }
    define_method("#{classname.downcase.pluralize}_count") { self.send("#{classname.to_s.downcase}_taggings".intern).length }
  end
      
end


# A module to map relationships, a little like ActiveRecord::Relation
# This is necessary because Contentful::Link classes are not 2-way, so you can't
# get the parent from a child.
module ContentfulModel
  module Associations
    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      # has_many is called on the parent model, and sets an instance var on the child
      # which is named the plural of the class this module is mixed into.
      #
      # e.g
      # class Foo
      #   has_many :bars
      # end
      # TODO this breaks down in situations where the has_many end doesn't respond to bars because the association is really the other way around
      # @param classname [Symbol] the name of the child model, as a plural symbol
      def has_many(classname, *opts)
        #define an instance method called the same as the arg passed in
        #e.g. bars()
        define_method "#{classname}" do
          # call bars() on super, and for each, call bar=(self)
          super().collect do |instance|
            instance.send(:"#{self.class.to_s.singularize.underscore}=",self)
            #return the instance to the collect() method
            instance
          end
        end
      end

      # has_one is called on the parent model, and sets a single instance var on the child
      # which is named the singular of the class this module is mixed into
      # it's conceptually identical to `has_many()`
      def has_one(classname, *opts)
        define_method "#{classname}" do
          if super().respond_to?(:"#{self.class.to_s.singularize.underscore}=")
            super().send(:"#{self.class.to_s.singularize.underscore}=",self)
          end
          super()
        end
      end


      # belongs_to is called on the child, and creates methods for mapping to the parent
      # @param classname [Symbol] the singular name of the parent
      def belongs_to(classname, *opts)
        raise ArgumentError, "belongs_to requires a class name as a symbol" unless classname.is_a?(Symbol)
        define_method "#{classname}" do
          #this is where we need to return the parent class
          self.instance_variable_get(:"@#{classname}")
        end

        define_method "#{classname}=" do |instance|
          #this is where we need to set the class name
          self.instance_variable_set(:"@#{classname}",instance)
        end
      end

      #belongs_to_many is really the same as has_many but from the other end of the relationship.
      #Contentful doesn't store 2-way relationships so we need to call the API for the parent classname, and
      #iterate through it, finding this class. All the entries will be put in an array.
      # @param classnames [Symbol] plural name of the class we need to search through, to find this class
      def belongs_to_many(classnames, *opts)
        if self.respond_to?(:"@#{classnames}")
          self.send(classnames)
        else
          define_method "#{classnames}" do
            parents = self.instance_variable_get(:"@#{classnames}")
            if parents.nil?
              #get the parent class objects as an array
              parent_objects = classnames.to_s.singularize.classify.constantize.send(:all).send(:load)
              #iterate through parent objects and see if any of the children include the same ID as the method
              parents = parent_objects.select do |parent_object|
                #check to see if the parent object responds to the plural or singular
                if parent_object.respond_to?(:"#{self.class.to_s.pluralize.underscore}")
                  #if it responds to the plural, check if the ids in the collection include the id of this child
                  parent_object.send(:"#{self.class.to_s.pluralize.underscore}").collect(&:id).include?(self.id)
                else
                  #if it doesn't respond to the plural, assume singular
                  parent_object.send(:"#{self.class.to_s.underscore}").id == self.id
                end
              end
              self.instance_variable_set(:"@#{classnames}",parents)
            end
            parents
          end
        end
      end
    end
  end
end
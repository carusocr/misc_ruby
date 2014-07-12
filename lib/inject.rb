# Return true if all elements are equal to the argument, false otherwise.
def all_equal?(argument, elements)
  a = true 
  elements.inject(argument) { |z,x| a = false if z != x; x }
  a
end

# Return the number of elements that are equal to the argument.
def count_equal(argument, elements)
  elements.inject(0) { |count, elem| elem == argument ? count+1 : count }
end

# Find keys in a nested hash using an array key.
#
# Example:
#   nested_key([:outer, :inner], { outer: { inner: 'value' } })
#   # => 'value'
def nested_key(keys, hash)
  # TODO: implement using inject
end

class Category < ActiveRecord::Base
  belongs_to :parent, class_name: 'Category'
  has_many :children, class_name: 'Category', foreign_key: 'parent_id'

  # Find categories where the body matches a space-separated list of words.
  #
  # For example, the query "hey there" should match any category with a body
  # containing both "hey" and "there."
  def self.search(query)
    # TODO: rewrite to use inject instead of each and mutation
    relation = self
    query.split(' ').each do |keyword|
      relation = relation.where('body LIKE ?', "%#{keyword}%")
    end
    relation
  end

  # Find categories using a slash-separated list of names.
  #
  # For example, the path "Parent/Child" will find a category named "Child"
  # within a parent category named "Parent."
  def self.find_by_path(path)
    # TODO: implement using inject
  end

  private

  def self.children
    all
  end
end

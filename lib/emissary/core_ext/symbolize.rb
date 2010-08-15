class Array
  def symbolize
    collect do |value|
      case value
        when Hash, Array
          value.symbolize
      else
        value
      end
    end
  end
  
  def symbolize!
    self.replace(self.symbolize)
  end
end

class Hash
   def symbolize
    inject({}) do |hash,(key,value)|
      hash[(key.to_sym rescue key) || key] = case value
        when Hash, Array
          value.symbolize
        else
          value
      end
      hash
    end
  end
  def symbolize!
    self.replace(self.symbolize)
  end
end

class Hash
   def symbolize
    inject({}) do |hash,(key,value)|
      hash[(key.to_sym rescue key) || key] = (value.kind_of?(Hash) ? value.symbolize : value)
      hash
    end
  end
  def symbolize!
    self.replace(self.symbolize)
  end
end

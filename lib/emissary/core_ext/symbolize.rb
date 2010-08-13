class Hash
   def symbolize
    inject({}) do |hash,(key,value)|
      hash[(key.to_sym rescue key) || key] = case value
        when Hash
          value.symbolize
        when Array
          value.collect { |v| v.symbolize rescue v }
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

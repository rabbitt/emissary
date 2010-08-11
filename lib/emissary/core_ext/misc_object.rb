##### BORROWED FROM ACTIVESUPPORT #####

class Object
  def __method__
    caller[0] =~ /\d:in `([^']+)'/
    $1.to_sym rescue nil
  end

  def __caller__
    caller[1] =~ /\d:in `([^']+)'/
    $1.to_sym rescue nil
  end

  def clone_deep
    Marshal.load(Marshal.dump(self)) rescue self.clone
  end
end

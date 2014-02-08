require './docgen.rb'

docgrp = {};

Dir["*.lua"].each{|a|
	doc = DocReader.Open(a)
	docgrp[doc.group[0]] = [] if (docgrp[doc.group[0]]) == nil
	docgrp[doc.group[0]] << doc;
}

docgrp.each_pair{|key, docs|
	outp = File.new("#{key}.dot", File::CREAT | File::RDWR)
	outp.print("graph api {\
	node [shape=box,style=filled];\n")

	docs.each{|a|
		outp.print("#{a.name};\n")
		a.related.each{|b|
			b.split(",").each{|c|
				outp.print("#{a.name} -- #{c};\n")
			}
		}
	}
	outp.print("}\n")
	outp.close
}




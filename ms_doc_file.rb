
require 'ms_comp_file'
require 'ms_fib'

class APcd < BinData::Record
  endian :little
  uint8 :fNoParaLast     # only first bit matters (0x01)
  uint8 :fR2
  uint32 :fc
  uint16 :prm
  def fCompressed
    (fc & 0x40000000)==0x40000000
  end
  def offset
    ofs = (fc & 0x3ffffff)
    ofs = (fc & 0x3ffffff)/2 if fCompressed
    ofs
  end
end

class Fld < BinData::Record
  endian :little
  uint8 :fldch
  uint8 :grffld
end

class FBKF < BinData::Record
  endian :little
  uint16 :ibkl
  struct :bkc do
    bit7 :itcFirst
    bit1 :fPub
    bit6 :itcLim
    bit1 :fNative
    bit1 :fCol
  end
end

class SprmOpcode < BinData::Record
       # 6A03 => 0110 1010 0000 0011 | ispmd=3 | fSpec=1 | sType=2 | spra=3
  bit9 :ispmd
  bit1 :fSpec
  bit3 :sType
  bit3 :spra
end

class Xstz < BinData::Record
  endian :little
  uint16 :cch
  array :rgtchar, :type=>:uint16, :initial_length => :cch
  uint16 :zero

  def get
    rgtchar.to_a.pack('U*')
  end
end

class STTBx < BinData::Record
  endian :little
  uint16 :fExtend, :asserted_value => 0xffff      # must be 0xffff
  uint16 :cData
  uint16 :cbExtra
  array :sttb, :initial_length => :cData do
    uint16 :cchData
    array :data, :type=>:uint16, :initial_length => :cchData
    array :extraData, :type=>:uint8, :initial_length => :cbExtra
  end
end

class FFDataBits < BinData::Record
  endian :little
  # low byte
  bit1 :fOwnHelp
  bit5 :iRes
  bit2 :iType
  # high byte
  bit1 :fHasListBox
  bit1 :fRecalc
  bit3 :iTypeTxt
  bit1 :iSize
  bit1 :fProt
  bit1 :fOwnStat
end

class FormFieldData < BinData::Record
  endian :little
  uint32 :version
  FFDataBits :ffdb
  uint16 :cch
  uint16 :hps
  Xstz :xstzName
  Xstz :xstzTextDef, :onlyif => lambda { ffdb.iType==0 }
  uint16 :wDef, :onlyif => lambda { ffdb.iType==1 or ffdb.iType==2 }
  Xstz :xstzTextFormat
  Xstz :xstzHelpText
  Xstz :xstzStatText
  Xstz :xstzEntryMcr
  Xstz :xstzExitMcr
  STTBx :hsttbDropList, :onlyif => lambda { ffdb.iType==2 }
end


class MsDocFile

  attr_reader :fib
  attr_reader :compfile
  attr_reader :table
  attr_reader :clx
  attr_reader :acp
  attr_reader :apcd
  attr_reader :formfields
  attr_reader :maindoc

  def initialize fname
    @compfile = MsCompFile.new fname
    @fib = MsFIB::new
    parse
  end

  def text
    @text
  end

  def fields finame
    @formfields.each do |ff|
      return ff.values[0] if ff.keys[0] == finame
    end
    raise "Unknown formfield name given! [#{finame}]"
  end

  # read piecetable
  def read_clx
    bidx = 0
    while bidx<@clx.length do
      if @clx[bidx]=="\x02"
        #puts "Pcdt found"
        # found Pcdt!
        # read 4 bytes lcb (length of PlcPcd)
        bidx+=1
        lcb = @clx[bidx..bidx+3].unpack('l')[0]
        #puts "lcb = #{lcb}"
        # read aCP array
        other_ccp = @fib.fibRgLw97.ccpFtn+@fib.fibRgLw97.ccpHdd+@fib.fibRgLw97.ccpMcr+
            @fib.fibRgLw97.ccpAtn+@fib.fibRgLw97.ccpEdn+@fib.fibRgLw97.ccpTxbx+
            @fib.fibRgLw97.ccpHdrTxbx
        last_cp = (other_ccp!=0) ? @fib.fibRgLw97.ccpText+1+other_ccp : @fib.fibRgLw97.ccpText
        last_acpi = (lcb-4)/(8+4)
        #puts "last_cp = #{last_cp}        other_ccp = #{other_ccp}"
        bidx+=4
        acpi = 0
        @acp = []
        begin
          cp = @clx[bidx..bidx+3].unpack('l')[0]
          #puts "#{acpi}. cp = #{cp}"
          @acp << cp
          acpi+=1
          bidx+=4
        end while (acpi<last_acpi+1)
        # now aPcd array
        @apcd = []
        apcdi = 0
        while apcdi<(last_acpi) do
          apcd = APcd.read(@clx[bidx..bidx+7])
          #puts "#{apcdi}. apcd = #{apcd.inspect}"
          @apcd << apcd
          apcdi+=1
          bidx+=8
        end
        break     # we've done
      else
        # found Prc structure
        # read uint16 & skip that no. bytes
        bidx+=1
        skip = @clx[bidx..bidx+1].unpack('s')[0]
        bidx+=skip
        #puts "Prc found, skipped #{skip} bytes..."
      end
    end
  end

  # read PLC type table
  #   @plcbuf -> PLC data
  #   @plclen -> length of PLC data
  #   @cbdata -> data item size
  #   @dataclass -> class of data item (for instantiation)
  def read_plex stream, fc, lcb, cbdata, dataclass
    cItems = (lcb-4)/(4+cbdata)
    cps = []
    items = []
    idx = fc
    ci = 0
    while ci < cItems+1
      cps << stream[idx..idx+3].unpack('l')[0]
      idx+=4
      ci+=1
    end
    ci=0
    if cbdata>0
      while ci < cItems
        item = dataclass.new
        item.read(stream[idx..idx+cbdata-1])
        idx+=cbdata
        items << item
        ci+=1
      end
    end
    return cps, items
  end

  # sttb
  def read_sttb stream, fc, lcb, dataclass=nil
    #puts "STTB @ : #{'%d' % fc} len= #{'%d' % lcb}"
    # read fExtend
    ext = false
    items = []
    idx = fc
    fExt = stream[idx..idx+1].unpack('S')[0]
    #puts "fExtend : #{'%x' % fExt}"
    if fExt==0xffff
      # extended Sttb
      ext = true
      idx+=2
      cData = stream[idx..idx+1].unpack('S')[0]
      idx+=2
    else
      # simple Sttb
      cData = stream[idx..idx+3].unpack('L')[0]
      idx+=4
    end
    #puts "cData : #{'%x' % cData}"
    cbExtra = stream[idx..idx+1].unpack('S')[0]
    idx+=2
    #puts "cbExtra : #{'%x' % cbExtra}"
    i=0;
    while i<cData
      if ext
        cchData = stream[idx..idx+1].unpack('S')[0]
        cbData = cchData*2
        idx+=2
      else
        cchData = stream[idx..idx].unpack('C')[0]
        cbData = cchData
        idx+=1
      end
      ec = Encoding::Converter.new('UTF-16LE', 'UTF-8')
      #puts "item : #{i} : cch=#{'%x' % cchData} len=#{'%x' % cbData}"
      if dataclass.nil?
        item=stream[idx..idx+cbData-1]
        item = ec.convert(item.force_encoding('UTF-16LE')) if ext
        item = item.force_encoding('UTF-8') if !ext
      else
        item = dataclass.new
        item.read(stream[idx..idx+cbData-1])
      end
      idx+=cbData
      items << item
      idx+=cbExtra  # skip Extra bytes
      i+=1
    end
    return items
  end


  def read_fibptrbuf stream,ptr,lcb
    @compfile.read_from(stream)[ptr..ptr+lcb-1]
  end

  def read_bytes stream, fc, lcb
    stream[fc..fc+lcb-1]
  end


  def parse
    # read WordDocument stream
    @worddoc = @compfile.read_from('WordDocument')
    # read Data stream
    @data = @compfile.read_from('Data')
    # read FIB structures
    @fib.read(@worddoc)
    # check for wIdent
    raise 'WordDocument stream format unknown!' if @fib.fibBase.wIdent!=0xA5EC
    # read 1/0Table
    @table = @compfile.read_from "#{@fib.fibBase.bfA.fWhichTblStm.to_i.to_s}Table"
    # read Clx array
    @clx = @table[@fib.fibRgFcLcbBlob.fcClx..@fib.fibRgFcLcbBlob.fcClx+@fib.fibRgFcLcbBlob.lcbClx-1]
    read_clx
    # read FldMom - fields of main document
    @fldcps, @fldflds = read_plex @table,@fib.fibRgFcLcbBlob.fcPlcfFldMom, @fib.fibRgFcLcbBlob.lcbPlcfFldMom, 2, Fld
    # parse fields :)
    @fldflds.each do |f|
      f.fldch = f.fldch & 0x1f
    end

    # bookmarks [fcSttbfBkmk]
    @mombkmk = read_sttb @table, @fib.fibRgFcLcbBlob.fcSttbfBkmk, @fib.fibRgFcLcbBlob.lcbSttbfBkmk
    # bookmarks' plexes
    @plcfbkf_cp, @plcfbkf_fbkf = read_plex @table, @fib.fibRgFcLcbBlob.fcPlcfBkf, @fib.fibRgFcLcbBlob.lcbPlcfBkf, 4, FBKF
    @plcfbkl_cp, ignore = read_plex @table, @fib.fibRgFcLcbBlob.fcPlcfBkl, @fib.fibRgFcLcbBlob.lcbPlcfBkl, 0, nil

    # read texts :)
    @maindoc = []

    ec = Encoding::Converter.new('UTF-16LE', 'UTF-8')

    @fc_of_cp = {}    # file_offsets of each character position in maindoc
    @cp_of_fc = {}    # character positions of each file offset in maindoc

    @apcd.each_index do |i|
      txln = @acp[i+1]-@acp[i]
      if @apcd[i].fCompressed
        @maindoc << @worddoc[@apcd[i].offset..@apcd[i].offset+txln-1].force_encoding('UTF-8')
        for cpi in 0..txln
          @fc_of_cp[@acp[i]+cpi] = @apcd[i].offset+cpi
          @cp_of_fc[@apcd[i].offset+cpi] = @acp[i]+cpi
        end
      else
        @maindoc << ec.convert(@worddoc[@apcd[i].offset..@apcd[i].offset+txln*2-1].force_encoding('UTF-16LE'))
        for cpi in 0..txln
          @fc_of_cp[@acp[i]+cpi] = @apcd[i].offset+cpi*2
          @cp_of_fc[@apcd[i].offset+cpi*2] = @acp[i]+cpi
        end
      end
    end

    @fkpchpx = []
    # find CHPXs
    btChpx = read_bytes @table, @fib.fibRgFcLcbBlob.fcPlcfBteChpx, @fib.fibRgFcLcbBlob.lcbPlcfBteChpx
    n = ((@fib.fibRgFcLcbBlob.lcbPlcfBteChpx-4)/8)+1
    i = n*4
    while i<@fib.fibRgFcLcbBlob.lcbPlcfBteChpx
      fkpidx = btChpx[i..i+3].unpack('L')[0]
      fc = fkpidx*512
      # read 512 bytes of FKP & fc on WordDocument stream
      fkpSector = read_bytes @worddoc,fc,512
      crun = fkpSector[511].unpack('C')[0]    # run count (crun)
      rgfc = []
      fkpi = 0
      for rgfci in 0..(crun)
        rgfc[rgfci] = fkpSector[fkpi..fkpi+3].unpack('L')[0]
        fkpi+=4
      end
      rgb = []
      grpchpx = []
      fkpi = 4*(crun+1)
      for rgbi in 0..(crun-1)
        wo = fkpSector[fkpi].unpack('C')[0]
        rgb[rgbi] = wo
        fkpi+=1
        if wo!=0
          cb = fkpSector[wo*2].unpack('C')[0]
          grpchpx[rgbi] = parseChpxs(fkpSector[wo*2+1..wo*2+1+cb-1])    # this is the CHPX !!!
        else
          grpchpx[rgbi] = []    # empty CHPX (not "modifying")
        end
      end
      @fkpchpx << { :rgfc => rgfc, :rgb => rgb, :grpchpx => grpchpx }
      i+=4
    end

    # parse main document
    @formfields = []
    @text = ""
    cp = 0

    while cp < @fib.fibRgLw97.ccpText
      c = getCharAtCp cp    # returned char will be UTF-8
      ci = c.unpack('C')[0]
      #print '%d : ' % cp
      if ci == 19
        #print 'F'
        # we've found FieldBegin mark
        cpfs = cp
        cpfp = findNextCpWith cpfs, 20      # find separator's Cp
        cpfe = findNextCpWith cpfs, 21
        fcode = ""  # whole field def in worddoc
        (cpfs..cpfe).each { |cpf| fcode << getCharAtCp(cpf) }
        fcode = fcode.force_encoding('UTF-8') # make sure :)
        if fcode['FORM']  # check for FORM* instrText
          # FORM[text][checkbox][list] found
          cpPic = findNextCpWith cpfs, 1      # search for Picture textmark
          if (cpPic<cpfe)
            # valid
            #puts "| FORM @ #{cpfs}-#{cpfp}-#{cpfe} cpPic:#{cpPic}"
            fcPic = @fc_of_cp[cpPic]
            chpxpic = getChpxs(fcPic, fcPic+1)[0]
            #puts "| CHPX: #{chpxpic.inspect}"
            npabd = getNPABD(chpxpic, @data)    # retrieve NilPicfAndBinData
            ffdata = FormFieldData.new
            #puts "| npabd: #{npabd.inspect}"
            ffdata.read(npabd[:binData])
            #puts "| fcode : | #{fcode.encode('UTF-8')}"
            #puts " FFData : #{ffdata.xstzName.get}"
            # have whole field data
            if ffdata.ffdb.iType==0
              finame = "FT_#{ffdata.xstzName.get}"
              firesult = fcode[cpfp-cpfs+1..fcode.length-2]
              #puts " #{finame.encode('UTF-8')} => #{firesult.encode('UTF-8')} "
              @formfields << {finame.encode('UTF-8') => firesult.encode('UTF-8')}
              @text << firesult.encode('UTF-8')
            elsif ffdata.ffdb.iType==1
              finame = "FC_#{ffdata.xstzName.get}"
              if ffdata.ffdb.iRes!=25
                firesult = ffdata.ffdb.iRes.to_s
                @text << (firesult=='1' ? '[X]' : '[ ]')
              else
                firesult = ""
                @text << '[ ]'
              end
              @formfields << {finame.encode('UTF-8') => firesult.encode('UTF-8')}
            elsif ffdata.ffdb.iType==2
              finame = "FL_#{ffdata.xstzName.get}"
              if ffdata.ffdb.iRes!=25   # undef entry
                firesult = ffdata.hsttbDropList.sttb[ffdata.ffdb.iRes].data.to_a.pack('C*')
                @text << "[#{firesult}]"
              else
                firesult = ""
                @text << "[ ]"
              end
              @formfields << {finame.encode('UTF-8') => firesult.encode('UTF-8')}
            end
            cp = cpfe
          end
        end
        #fields.merge!({:fcode => fcode, :cps=>cpfs, :cpe=>cpfe })
      else
        #print '%d' % c.unpack('C')[0]
        # recode special characters into something more beautiful :)
        if c == "\b" or ci==1
          @text << ' [pic] '
        elsif c == "\a" or c == "\r" or c == "\v"
          @text << "\n"
        elsif c == "\t"
          @text << '    '
        else
          begin
            @text << c
          rescue
            #puts "#{c} => #{ci} @ cp=#{cp}"
            c=" "
            retry
          end
        end
      end
      #print c.encode('UTF-8')
      cp+=1
    end
  end

  def parseChpxs buf
    # parse PropertyExceptions in given buf
    return [] if buf.length==0
    grpprl = []
    sprmS = 0
    more = true
    while more
      if (sprmS+2) < buf.length
        opcode = buf[sprmS..sprmS+1].unpack('S')[0]
        spra = opcode >> 13
        opsize = [1,1,2,4,2,2,255,3,0][spra]
        len = 0
        if opsize==255
          if opcode==0xd608 || opcode==0xd606     #sprmTDefTable || sprmTDefTable10
            len = 2
            opsize = buf[sprmS+2..sprmS+3].unpack('S')[0]
            opsize-=1
          elsif opcode==0xc615                    #sprmPChgTabs
            len=1
            opsize = buf[sprmS+2]
            if opsize==255
              itbdDelMax=buf[sprmS+3].unpack('C')[0]
              itbdAddMax=buf[sprmS+3+2*itbdDelMax].unpack('C')[0]
              opsize = (itbdDelMax*4+itbdAddMax*3)-1
            end
          else
            len = 1
            opsize = buf[sprmS+2].unpack('C')[0]
          end
        end
        sprmLen = 2+len+opsize
        if buf.length>=sprmS+sprmLen
          sprmBuf = buf[sprmS..sprmS+sprmLen-1]
          # parse sprm & add to grpprl
          grpprl << parseSprm(sprmBuf)
          sprmS += sprmBuf.length
        else
          more = false
        end
      else
        more = false
      end
    end
    return grpprl
  end

  def parseSprm sbuf
    #puts "parseSprm : #{sbuf}"
    sprm = {}
    op = SprmOpcode.new
    o = sbuf[0..1].unpack('S')[0]
    #op.read(sbuf[0..1])
    op.ispmd = o & 0x1ff
    op.fSpec = o[9]
    op.sType = o[10]+o[11]*2+o[12]*4
    op.spra = o[13]+o[14]*2+o[15]*4
    sprm[:opcode] = op
    sprm[:opc] = sbuf[0..1].unpack('S')[0]
    #puts "opcode = #{op.inspect} = #{sprm[:opc]}"
    opsize = [1,1,2,4,2,2,255,3,0][op.spra]
    #puts "opsize = #{opsize}"
    if opsize==255
      if sprm[:opc]==0xd608 || sprm[:opc]==0xd606     #sprmTDefTable || sprmTDefTable10
        opsztbl = sbuf[2..3].unpack('S')[0]
        args = sbuf[4..4+opsztbl-1-1]   # args are opsztbl-1
      elsif sprm[:opc]==0xc615                    #sprmPChgTabs
        alen = sbuf[2].unpack('C')[0]
        args = sbuf[3..3+alen-1]
      else
        opsize = sbuf[2].unpack('C')[0]
        args = sbuf[3..3+opsize-1]
      end
    else
      args = sbuf[2..2+opsize-1]
    end
    sprm[:opsize] = opsize
    sprm[:args] = args
    return sprm
  end

  def getNPABD grpprl, dataStream
    # find fcPIC for given grpprl array
    fc = -1
    grpprl.each do |sprm|
      #puts "|| #{sprm.inspect}"
      if sprm[:opc]==0x6A03      # sprmCPicLocation
        fc = sprm[:args][0..3].unpack('L')[0]
      elsif sprm[:opc]==0x6A12   # sprmCHsp
        fc = sprm[:args][0..3].unpack('L')[0]
      end
    end
    if fc!=-1
      #puts "| HAVE fcPIC @ #{fc} "
      # found fcPIC
      lcb = dataStream[fc..fc+3].unpack('L')[0]
      fc+=4
      cbHeader = dataStream[fc..fc+1].unpack('S')[0]
      fc+=2
      fc+=62  # skip 62 bytes
      binData = dataStream[fc..fc+lcb-cbHeader-1]
      return {:lcb=>lcb, :cbHdr=>cbHeader, :binData=>binData}
    end
  end

  def getChpxs fcmin, fcmax
    lst = []
    @fkpchpx.each do |fkp|
      fkp[:grpchpx].each_index do |j|
        if fkp[:rgfc][j]<fcmin && fkp[:rgfc][j+1]>fcmin
          lst << fkp[:grpchpx][j]
        else if fkp[:rgfc][j]>=fcmin && fkp[:rgfc][j]<fcmax
               lst << fkp[:grpchpx][j]
             end
        end
      end
    end
    return lst
  end

  #@param startCp - where to start with search
  #@param char - what to find as first found occurrence
  def findNextCpWith startCp, char
    cp = startCp
    while cp < @fib.fibRgLw97.ccpText
      if getCharAtCp(cp).unpack('C')[0]==char
        return cp
      end
      cp+=1
    end
    # character not found - return invalid CP
    return -1
  end

  def findApcd cp
    # find apcd for cp
    @apcd.each_index do |i|
      if cp>=@acp[i] && cp<@acp[i+1]
        # we've found proper apcd
        #print "#{cp}=>i(#{i}) "
        return @apcd[i]
      end
    end
  end

  def getCharAtCp cp
    # check if range of cp in apcd is fCompressed or not
    # find apcd for cp
    to8 = Encoding::Converter.new('UTF-16LE','UTF-8')
    apcd = findApcd cp
    #puts "APCD: #{apcd.inspect}"
    if apcd.fCompressed
      ch = @worddoc[@fc_of_cp[cp]].force_encoding('ISO-8859-2').encode('UTF-8')
    else
      ch = to8.convert(@worddoc[@fc_of_cp[cp]..@fc_of_cp[cp]+1].force_encoding('UTF-16LE'))
    end

    #begin
    #  ch.encode!('UTF-8') if ch.encoding!='UTF-8'
    #rescue
    #  puts "#{ch} (#{ch.unpack('C')[0]}) in #{ch.encoding} @ cp=#{cp}"
    #end

    return ch
  end

end

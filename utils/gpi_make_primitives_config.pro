;+ 
; NAME:  make_primitives_config
; DESCRIPTION:
;
;   Create primitives_config.xml file with all primitives available 
;   for GPI, based on scanning comment headers in the primitive source code.
;
; INPUTS:
; 	None, reads primitives source code from disk and parses headers
; KEYWORDS:
;	/sortbyorder	Sort primitives by their nominal execution order, rather
;					than the default alphabetical order.
; OUTPUTS:
; 	writes a new primitives_config.xml to disk
;
; HISTORY:
;   Began 2009-09-14 : JMaire based on  make_DRSConfigXML.py
;   2012-01-30 MP: Updated paths to write to $GPI_DRP_CONFIG_FILE
;   2012-08-17 MP: Renamed to make_primitive_config, added /sortbyorder option,
;   				and converted XML output to Gemini nomenclature of
;   				primitives and recipes. Major change.
;   2013-04-29 MP: Added some checks for '&' characters in XML strings which are
;   			   not allowed. Converts them to 'and' rather than trying to
;   			   escape them since I don't see a need to render an '&' as part
;   			   of a primitive description in the UI, and I'm not sure
;   			   exactly how IDL's SAX XML parser would handle that. Easiest
;   			   to just avoid the problem entirely since this is not an
;   			   important use case. 
;   2013-07-12 MP: Documentation update
;
;
;-


pro gpi_make_primitives_config, sortbyorder=sortbyorder

	;Scan through the various IDL *.pro files looking for magic strings
	;    which mark the description and argument strings to use in the GUI.

	directory=gpi_get_directory('GPI_DRP_DIR')+path_sep()+'primitives'
	list = FILE_SEARCH(directory+path_sep()+'[A-Za-z]*.pro',count=cc) 
	if cc eq 0 then begin 
		print, "ERROR: No *.pro files were found in "+directory
	  endif else begin
		print, "    Scanning for *.pro files in "+directory
		print, strc(cc), ' files were found'
	endelse

	primitivespro=strarr(cc)
	primitivesName=strarr(cc)
	primitivesdescrip=strarr(cc)
	primitivescomment=strarr(cc)
	primitivesorder=strarr(cc)
	primitivestype=strarr(cc)
	;primitivessequence=strarr(cc)
	;primitives={modnum:0, arg:''}
	argument=ptr_new(/ALLOCATE_HEAP)
	;IF N_ELEMENTS(*Self.Modules) EQ 0 THEN $
	;    *Self.Modules = {name: moduleName, idlfunc: moduleFunction} $
	;  ELSE *Self.Modules = [*Self.Modules, {name: moduleName, idlfunc: moduleFunction}]

	for i=0, cc-1 do begin
	var1=''
	primitivespro[i]=FILE_BASENAME(list[i], '.pro')
	  OPENR, Unit, list[i], /GET_LUN
	  WHILE ~ EOF(Unit) DO BEGIN
		readF, Unit, var1   
		if stregex(var1,'Name:',/fold_case,length=l) ne -1  then begin
			primitivesName[i]=strtrim(STRMID(var1, l+2),2)
		endif    
		if stregex(var1,'PIPELINE PRIMITIVE DESCRIPTION:',/fold_case,length=l) ne -1  then begin
			primitivesdescrip[i]=strtrim(STRMID(var1, l+2),2)
		endif    
		if stregex(var1,'COMMENT:',/fold_case,length=l) ne -1  then begin
			primitivescomment[i]=STRMID(var1, l+11)
		endif 
		if stregex(var1,'ORDER:',/fold_case,length=l) ne -1  then begin
			primitivesorder[i]=STRMID(var1, l+11)
		endif 
		;if stregex(var1,'TYPE:',/fold_case,length=l) ne -1  then begin
		; This is back compatibility for the old terminology, can probably
		; be removed
		if (stregex(var1,'NEWTYPE:',/fold_case,length=l) ne -1) then begin
			primitivestype[i]=STRMID(var1, l+11)
		endif 
		if (stregex(var1,'CATEGORY:',/fold_case,length=l)) ne -1  then begin
			primitivestype[i]=STRMID(var1, l+11)
		endif 
	
		;if stregex(var1,'SEQUENCE:',/fold_case,length=l) ne -1  then begin
			;primitivessequence[i]=STRMID(var1, l+11)
		;endif 
		if stregex(var1,'ARGUMENT:',/fold_case,length=l) ne -1  then begin
			IF N_ELEMENTS(*argument) EQ 0 THEN $
				*argument = {modnum: i, arg: STRMID(var1, l+11)} $
				ELSE *argument = [*argument, {modnum: i, arg: STRMID(var1, l+11)}]
		endif     

		endwhile
		
		nspaces = 40 - strlen(primitivespro[i])
		spaces = strmid('                                            ',0,nspaces) ; is there a better way to do this?

		;print, "Found module "+primitivespro[i]+".pro:      "+primitivesdescrip[i]
		print, primitivespro[i]+spaces+string(09b)+primitivesdescrip[i]
		close, Unit
		Free_Lun, Unit
	endfor

	; Enforce character restrictions for XML:
	; No bare ampersands allowed!
	for i=0, cc-1 do begin
		if strpos(primitivesdescrip[i], '&') gt 0 then primitivesdescrip[i] = strepex(primitivesdescrip[i], '&', 'and',/all)
		if strpos(primitivescomment[i], '&') gt 0 then primitivescomment[i] = strepex(primitivescomment[i], '&', 'and',/all)
	endfor

	outputfile = gpi_get_directory('GPI_DRP_CONFIG_DIR')+path_sep()+'gpi_pipeline_primitives.xml'
	outputfile = repstr(outputfile, path_sep()+path_sep(), path_sep()) ; clean up erroneous duplicate path seps which openw will fail on
	;generate DRSconfig
	 print, "  ===>>> Saving config XML to "+outputfile 
	 OpenW, lun, outputfile, /Get_Lun
			 PrintF, lun, '<Config >'
			 PrintF, lun, '<!-- GPI DRP Primitives Config File - for pipepine, recipe editor, etc. ' 
			 PrintF, lun, 'This file was autogenerated by make_primitive_config.pro based on IDL doc headers -->'
			 PrintF, lun, '<!-- Module Names to IDL functions map -->'
	 
	if keyword_set(sortbyorder) then begin
	 ;resort with order
	   indsortorder=   sort(float( primitivesorder))
	   sortedprimitivesdescrip=primitivesdescrip[indsortorder]
	   sortedprimitivespro=primitivespro[indsortorder]
	   sortedprimitivesorder=primitivesorder[indsortorder]
	endif
	 
 
    FOR i=0,(cc)-1 DO BEGIN
      argnum=where((*argument).modnum eq i,cm)
      if cm eq 0 then endline='" />' else endline='" >'
      PrintF, lun, ' <Primitive Name="'+primitivesdescrip[i]+'" IDLFunc="'+primitivespro[i]+'" Comment="'+primitivescomment[i]+$
      '" Order="'+primitivesorder[i]+'" Type="'+primitivestype[i]+ endline
      for j=1,cm do begin
        PrintF, lun, '     <Argument '+((*argument).arg)[argnum[j-1]]+' />'
      endfor
      if cm ne 0 then PrintF, lun, ' </Primitive>'
    ENDFOR
    PrintF, lun, '</Config>'    
    Free_Lun, lun


end

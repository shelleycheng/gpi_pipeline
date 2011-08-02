;+
; NAME:  save_currdata
;
; PURPOSE: save the dataset
;
; INPUT :  DataSet     : the DataSet pointer.
;          nFrames     : number of datasets
;          s_OutputDir : the output directory
;          s_Ext       : output filename extension (suffix)
;          /DEBUG      : initializes debugging mode
;
;          filenm=		 Filename for writing (to override default file name)
;
;          SaveData=     Save this data INSTEAD of the current DataSet pointer
;          SaveHeader=	 Extension Header for writing along with the SaveData data.
;          SavePHU=		 Primary header for writing along with the SaveData data.
;
; OUTPUT : Saves the dataset to disk
;
; STATUS : 
;
; HISTORY : 
;   2005-01-23, created by  Christof Iserlohe (iserlohe@ph1.uni-koeln.de) 
;   			as save_dataset.pro
;   2009-02 JM: Added Display keyword to call GPITVMS. 
;   2009-05 MDP: Documentation updated. 
; 	2010-01-27: Added code for GPI Calibrations DB. M. Perrin
; 	2011-03-16: Improved file name generation code. Split DATAFILE into
; 				DATAFILE and DATAPATH and switched to fxpar to support very
; 				long path names using the FITS CONTINUE convention.
; 	2011-08-01 MP: Revised for multi-extension FITS. save_currdata will now 
; 				always write its output as a primary header plus image
; 				extension. This is different from previous versions of the DRP!
; 				Switched to mwrfits instead of writefits because it better
; 				handles the EXTENT/XTENSION keywords needed for multi-ext FITS.
;
;-


function save_currdata, DataSet,  s_OutputDir, s_Ext, display=display, savedata=savedata, saveheader=saveheader, savePHU=savePHU, filenm=filenm, $
		output_filename=c_File1, level2=level2, addexten_var=addexten_var, addexten_qa=addexten_qa

    COMMON APP_CONSTANTS
    COMMON PIP

	getmyname, functionname
	version = gpi_pipeline_version()

    ;for i=0, nFrames-1 do begin
    if keyword_set(level2) then i=level2-1 else i=numfile

	;-- Generate output filename, starting from the input one.
	filnm=fxpar(*(DataSet.HeadersPHU[i]),'DATAFILE')
	
	s_OutputDir = gpi_expand_path(s_OutputDir) ; expand environment variables and ~s
	; test output dir
	if ~file_test(s_OutputDir,/directory, /write) then return, error("FAILURE: Directory "+s_OutputDir+" does not exist or is not writeable.",/alert)

	; If an extra path separator is present at the end, drop it:
	slash=strpos(filnm,path_sep(),/reverse_search)
	if slash ge 0 then begin
		c_File = s_OutputDir+strmid(filnm, slash,strlen(filnm)-5-slash)+s_Ext+'.fits'
	endif else begin
		dot = strpos(filnm,".",/reverse_search)
		c_file = s_OutputDir + path_sep() + strmid(filnm, 0, dot) + s_Ext+'.fits'
	endelse

    caldat,systime(/julian),month,day,year, hour,minute,second
    datestr = string(year,month,day,format='(i4.4,i2.2,i2.2)')
    hourstr = string(hour,minute,second,format='(i2.2,i2.2,i2.2)')  


	if ( NOT bool_is_string(c_File) ) then $
	   return, error('FAILURE ('+functionName+'): Output filename creation failed.')

	if ( strpos(c_File ,'.fits' ) ne -1 ) then $
	   c_File1 = strmid(c_File,0,strlen(c_File)-5)+'.fits' $
	else begin
	   warning, 'WARNING('+functionName+'): Filename is not fits compatible. Adding .fits.'
	   c_File1 = c_File+'_'+strg(i)+'.fits'
	end

	if ( keyword_set( filenm ) ) then  c_File1=filenm
	 ;update DATAFILE & DATAPATH keywords
  FXADDPAR,  *(dataset.headersPHU[numfile]), "DATAFILE", file_basename(c_File1), "File name"
  FXADDPAR,  *(dataset.headersPHU[numfile]), "DATAPATH", file_dirname(c_File1), "Path of DRP input", before="END"
	
	;writefits, c_File1, float(*DataSet.Frames(i)), *DataSet.Headers[i]
	;writefits, c_File1, float(*DataSet.IntFrames(i)), /APPEND
	;writefits, c_File1, byte(*DataSet.IntAuxFrames(i)), /APPEND
	if ( keyword_set( savedata ) ) then begin 
	  if ~( keyword_set( saveheader ) ) then saveheader = *(dataset.headers[numfile])
	  ;if numext eq 1 then 
	  if ~( keyword_set( savePHU ) ) then savePHU = *(dataset.headersPHU[numfile])
		;if numext eq 0 then begin
		    ;fxaddpar, saveheader, 'DRPVER', version, 'Version number of GPI data reduction pipeline software'
		    ;fxaddpar, saveheader, 'DRPDATE', datestr+'-'+hourstr, 'Date and time of creation of the DRP reduced data [yyyymmdd-hhmmss]'
				  ;writefits, c_File1, savedata, saveheader
		;endif else begin
		fxaddpar, savePHU, 'DRPVER', version, 'Version number of GPI data reduction pipeline software'
		fxaddpar, savePHU, 'DRPDATE', datestr+'-'+hourstr, 'Date and time of creation of the DRP reduced data [yyyymmdd-hhmmss]'
		;fxaddpar, savePHU, 'EXTEND', 'T', 'FITS file contains extensions'
		;fxaddpar, savePHU, 'NEXTEND', 1, 'FITS file contains extensions'
		;writefits, c_File1, 0, savePHU ;*(dataset.headersPHU[numfile])
		;writefits, c_File1, savedata, saveheader, /append
		mwrfits, 0, c_File1, savePHU, /create
		mwrfits, savedata, c_File1, saveheader
 
		;endelse
		curr_hdr = savePHU
		curr_ext_hdr = saveheader
	endif else begin
	  ;if numext eq 0 then begin
		  ;fxaddpar, *DataSet.Headers[i], 'DRPVER', version, 'Version number of GPI data reduction pipeline software'
		  ;fxaddpar, *DataSet.Headers[i], 'DRPDATE', datestr+'-'+hourstr, 'Date and time of creation of the DRP reduced data [yyyymmdd-hhmmss]'
      ;writefits, c_File1, *DataSet.currFrame, *DataSet.Headers[i]
          ;curr_hdr = *DataSet.Headers[i]
    ;endif else begin  
      	fxaddpar, *DataSet.HeadersPHU[i], 'DRPVER', version, 'Version number of GPI data reduction pipeline software'
      	fxaddpar, *DataSet.HeadersPHU[i], 'DRPDATE', datestr+'-'+hourstr, 'Date and time of creation of the DRP reduced data [yyyymmdd-hhmmss]'
		;fxaddpar, *DataSet.HeadersPHU[i], 'EXTEND', 'T', 'FITS file contains extensions'
		;fxaddpar, *DataSet.HeadersPHU[i], 'NEXTEND', 1, 'FITS file contains extensions'
		mwrfits, 0, c_File1, *DataSet.HeadersPHU[i], /create
		mwrfits, *DataSet.currFrame, c_File1, *DataSet.HeadersExt[i]
     	;writefits, c_File1, 0, *DataSet.HeadersPHU[i]
      	;writefits, c_File1, *DataSet.currFrame, *DataSet.HeadersExt[i], /append
      	curr_hdr = *DataSet.HeadersPHU[i]
      	curr_ext_hdr = *DataSet.HeadersExt[i]
    	;endelse  
      	DataSet.OutputFilenames[i] = c_File1  
	endelse

  if keyword_set(addexten_qa) then mwrfits, addexten_qa, c_File1
  if keyword_set(addexten_var) then mwrfits, addexten_var, c_File1
  
	if keyword_set(debug) then print, "  Data output ===>>> "+c_File1
	Backbone_comm->Log, "File output to: "+c_File1,/general,/DRF, depth=1

	;--- GPI Calibrations DB ----
	; Is this a calibration file? 
	;   (check both pri + ext headers just to be sure...)
	is_calib_pri = strc(strupcase(fxpar(curr_hdr, "ISCALIB"))) eq 'YES'
	is_calib_ext = strc(strupcase(fxpar(curr_hdr, "ISCALIB"))) eq 'YES'
	if is_calib_pri or is_calib_ext then begin
		gpicaldb = Backbone_comm->Getgpicaldb()
		if obj_valid(gpicaldb) then begin
			message,/info, "Adding file to GPI Calibrations DB."
			status = gpicaldb->Add_new_Cal( c_File1, header=curr_hdr)
		endif else begin
			message,/info, "*** ERROR: No Cal DB Object Loaded - cannot add file to DB ***"
		endelse
	endif

	;--- Update progress bar
	(Backbone_comm->Getprogressbar() )->set_suffix, s_Ext

  
	if ( keyword_set( display ) ) && (display ne 0) then Backbone_comm->gpitv, c_File1, ses=display


    return, OK

end

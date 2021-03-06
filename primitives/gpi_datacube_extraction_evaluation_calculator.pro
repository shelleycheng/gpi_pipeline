;+
; NAME: gpi_datacube_extraction_evaluation_calculator.pro
; PIPELINE PRIMITIVE DESCRIPTION: Evaluate the quality of a datacube extraction
;
; 	This primitive evaluates multiple aspects of datacube quality based on multiple metrics
; 	The metrics used depend on the type of input (either Arclamps or flat fields)
;
;	For arclamp data I recommend the dataset from 131208 - this has both arcs and flats taken at the same telescope position
;
; INPUTS: Some datacube
;
; OUTPUTS: The same datacube, unaffected 
;
; PIPELINE COMMENT: Calculate the quality of a datacube extraction based on multiple metrics.
; PIPELINE ARGUMENT: Name="Save" Type="int" Range="[0,1]" Default="0" Desc="1: save output on disk, 0: don't save"
; PIPELINE ARGUMENT: Name="gpitv" Type="int" Range="[0,500]" Default="0" Desc="1-500: choose gpitv session for displaying output, 0: no display "
; 
; where in the order of the primitives should this go by default?
; PIPELINE ORDER: 5.0
;
; pick one of the following options for the primitive type:
; PIPELINE CATEGORY: SpectralScience,Testing
;
; HISTORY:
;    2014-07-30 PI: create primitive
;-  

function gpi_datacube_extraction_evaluation_calculator, DataSet, Modules, Backbone
; enforce modern IDL compiler options:
compile_opt defint32, strictarr, logical_predicate

; don't edit the following line, it will be automatically updated by subversion:
primitive_version= '$Id$' ; get version from subversion to store in header history

calfiletype=''   ; set this to some non-null value e.g. 'dark' if you want to load a cal file.

; the following line sources a block of code common to all primitives
; It loads some common blocks, records the primitive version in the header for
; history, then if calfiletype is not blank it queries the calibration database
; for that file, and does error checking on the returned filename.
@__start_primitive
suffix='' 		 ; set this to the desired output filename suffix

; the metrics used will be dependent upon the type of image
; at the moment, only arclamp images are supported.	
cube=*dataset.currframe
	

if (backbone->get_keyword('OBSTYPE')) eq 'ARC' then begin

		; begin evaluation of extraction

		; pick 2 peaks and a trough
		; hardcoding for now based on Xenon.

		band = gpi_simplify_keyword_value(backbone->get_keyword('IFSFILT', indexFrame=numfile))
		; get the cube wavelengths	
		cwv=get_cwv(band)
		CommonWavVect=cwv.CommonWavVect
		lambda=cwv.lambda

		if band eq 'H' then begin
		    if strlowcase(strc(backbone->get_keyword('OBJECT'))) eq 'xe' then begin
			peak1=1.54226
			peak2=1.67327
			trough1=1.64 ; ballpark guess
			endif
			if strlowcase(strc(backbone->get_keyword('OBJECT'))) eq 'ar' then begin
			peak1=1.6945
			peak2=peak1
			trough1=1.57 ; ballpark guess
			endif
			if keyword_set(peak1) eq 0 then return, error('This is an ARC image but the Object header is not set to Xe nor Ar')
		; hoping Loren will do this, I'm just going to do something dirty

		; do a median filter on the image slice closest to peak 2

			junk=min(abs(lambda-peak2),sl1,/nan)  ; slice nearest the peak
			junk=min(abs(lambda-trough1),sl2,/nan)  ; slice nearest the peak

			slices=[sl1,sl2]

			for l=0,N_ELEMENTS(slices)-1 do begin
				; run a high-pass box filter
				im=cube[*,*,slices[l]]
				mask=finite(im)
				low_freq=filter_image(im,median=15,/all_pixels)*mask
			
					
				; now subtract the lowfrequency component
				tmp=im-low_freq
				print,''
				print, 'mean value of low_frequency slice at '+strc(lambda[slices[l]])+' = '+strc(mean(low_freq,/nan))
				print, 'stddev of low-frequency modulations of '+strc(lambda[slices[l]])+' = '+strc(stddev(low_freq,/nan))	
				print, 'stddev of high-frequency modulations of '+strc(lambda[slices[l]])+' = '+strc(stddev(tmp,/nan))
				print, 'percentage error of low-freq modulation ' +strc(stddev(low_freq,/nan)/mean(low_freq,/nan))
				print, 'percentage error of high-freq modulation ' +strc(stddev(tmp,/nan)/mean(low_freq,/nan))
				print,''
			
				; calculation of the number of extreme events
				
				tmp2=im/low_freq
				rs=robust_sigma(tmp2)
				
				;plothist,tmp2,/nan,bin=0.01
				
				med=mean(tmp2); this should be 1 by definition... but we compute it anyways (ZHD median resulted in zero once and caused infinity, switch to mean?)
				junk=where(tmp2 gt med+5*rs,n_bright_pix)
				print, 'Number of spaxels brighter than 5 sigma from their surroundings = '+strc(n_bright_pix)
				junk=where(tmp2 lt med-5*rs,n_bright_pix)
				print, 'Number of spaxels fainter than 5 sigma from their surroundings = '+strc(n_bright_pix)

				print,''

			endfor

			;stop

		

		endif

	;Adding a "checkerboard metric"

	id = where_xyz(finite(cube[*,*,0]),XIND=xarr,YIND=yarr)
	lens = [transpose(xarr),transpose(yarr)]

	;buffer a pixel column, falls out as -NaN
	cube = [cube[0:*,*,*],MAKE_ARRAY(1, 281, 37)]

	cms = [0]
	for i=0,n_elements(id)-1 do begin
		spec1 = cube[lens[0,i],lens[1,i],*]
		spec2 = cube[lens[0,i]+1,lens[1,i],*]
		cm = total(abs(spec1/total(spec1)-spec2/total(spec2)))
		if (finite(cm) EQ 1) then cms = [cms,cm]
	endfor
	
	bsize = 0.0025
	window,1
	cgHistoplot, cms, BINSIZE=0.0025, /FILL,xtitle="Checkerboard Metric",ytitle="# of lenslets",xrange=[0,0.15]
	print,'Checkerboard metric for full datacube"
	print,'Mean: ',mean(cms),'  STDDEV: ',stddev(cms)

	stop

endif ; end evaluation for arcs
	
	; The current headers (primary and extension) are available from the
	; pipeline backbone set_keyword and get_keyword functions. 
	; Using these functions saves you from having to worry about whether a 
	; given quantity is in the primary or extension HDU.
	;

	;backbone->set_keyword,'HISTORY',functionname+ " Multiplied datacube by a constant"
	;backbone->set_keyword,'MULTPLYR',multiplier, "Scalar value this datacube was multiplied by"


	itime = backbone->get_keyword('ITIME')

	; There is also a log function.
	;backbone->Log, "This image's exposure time is: "+string(itime)+" s"
	;backbone->Log, "This log message will be saved in the pipeline log, and displayed in the status console window."

; The following line also loads a block of code common to all primitives
; It saves the data to disk if the Save argument is set, and
; sends the data to a gpitv session if the gpitv argument is set.
;
; Optionally if a stopidl argument exists and is set, then stop 
; IDL at its command line debugger for interactive work. (This only
; works in source code IDL, not the compiled runtime.)
@__end_primitive

end

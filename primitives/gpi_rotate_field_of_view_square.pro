;+
; NAME: gpi_rotate_field_of_view_square
; PIPELINE PRIMITIVE DESCRIPTION: Rotate Field of View Square
;
;    Rotate by the lenslet/field relative angle, so that the GPI IFS 
;    field of view is roughly square with the pixel coordinate axes.
;
;
; INPUTS: detector image
; common needed: filter, wavcal, tilt, (nlens)
;
; KEYWORDS:
; GEM/GPI KEYWORDS:RA,DEC,PAR_ANG
; DRP KEYWORDS: CDELT1,CDELT2,CRPIX1,CRPIX2,CRVAL1,CRVAL2,NAXIS1,NAXIS2,PC1_1,PC1_2,PC2_1,PC2_2
; OUTPUTS:
;
; PIPELINE COMMENT: Rotate datacubes so that the field of view is squarely aligned with the image axes. 
; PIPELINE ARGUMENT: Name="Method" Type="enum" Range="CUBIC|FFT" Default="CUBIC"
; PIPELINE ARGUMENT: Name="crop" Type="int" Range="[0,1]" Default="0" Desc="Set to 1 to crop out non-illuminated pixels"
; PIPELINE ARGUMENT: Name="Show" Type="int" Range="[0,1]" Default="0"
; PIPELINE ARGUMENT: Name="Save" Type="int" Range="[0,1]" Default="0"
; PIPELINE ARGUMENT: Name="gpitv" Type="int" Range="[0,500]" Default="2" Desc="1-500: choose gpitv session for displaying output, 0: no display "
; PIPELINE ORDER: 3.9
; PIPELINE TYPE: ASTR/POL
; PIPELINE NEWTYPE: SpectralScience,PolarimetricScience
; PIPELINE SEQUENCE: 11-
;
; HISTORY:
;   2012-04-10 MDP: Created, based on rotate_north_up.pro
;-
function gpi_rotate_field_of_view_square, DataSet, Modules, Backbone
primitive_version= '$Id$' ; get version from subversion to store in header history
@__start_primitive

    cube=*(dataset.currframe[0])
    sz = size(cube)
    nslice = sz[3] ; works for either POL or SPEC modes


    if tag_exist( Modules[thisModuleIndex], "Method") then Method= strupcase(Modules[thisModuleIndex].method) else method="CUBIC" ; can be CUBIC or FFT
    if tag_exist( Modules[thisModuleIndex], "crop") then crop= strupcase(Modules[thisModuleIndex].crop) else crop=0 
    message,/info, " using rotation method "+method
	if method ne 'CUBIC' and method ne 'FFT' then return, error("Invalid rotation method: "+method)

    ; ====== Rotation =======
	; The angle by design ought to be atan(1,2), but in practice with the 
	; as built instrument there appears to be a slight offset from this.
	; Hence the following default:
	rotangle_d = gpi_get_constant('ifs_rotation', default=atan(1,2)*!radeg -2)
	; and we need to flip the sign here since we want to rotate back in the
	; opposite direction
	rotangle_d *= -1

    padsize=281
    cube0 =cube
    ; TODO more careful handling of center location here.
    
    xcen = (padsize-1)/2+1 & ycen = (padsize-1)/2+1

    ; In order to not have ugly ringing from the FFT rotation, we must
    ;  (a) not have any NaNs in the input data! and
    ;  (b) have the out-of-FOV regions match the in-the-FOV regions in intensity
    ;
    ; Therefore make a mask to look at the edges, and extrapolate this out
    ; everywhere. (TODO: a better/more careful job of this.)


    ; TODO masking of edges?
    ;  Need to have a better understanding of FFTROT boundary conditions
    ;  here
    ;  Enforce the same exact mask on both pols, for consistency
    ;zeromask = (cube[*,*,0] eq 0) or (cube[*,*,1] eq 0)
    badmask = ~(finite(total(cube,3))) ; any loc not good in ALL slices
    kernel = replicate(1,7,7)
    badmask2 = dilate(badmask, kernel)
    edgemask = badmask2-badmask
    sz = size(cube)
    cube_r = cube
    ; find where the bad region rotates to
    case method of
    'CUBIC': rotmask = rot(float(badmask), -rotangle_d,cubic=-0.5,/interp) gt 0.5
    'FFT': begin
        rotmask = fftrot(badmask, rotangle_d) gt 0.5
        ; mask out the corner regions outside the FOV too 
        rotmask[search2d(rotmask,0,0,0,0)]=1
        rotmask[search2d(rotmask,0,padsize-1,0,0)]=1
        rotmask[search2d(rotmask,padsize-1,0,0,0)]=1
        rotmask[search2d(rotmask,padsize-1,padsize-1,0,0)]=1
    end
    endcase


    for i=0L,nslice-1 do begin
        edgeval = median(cube[where(edgemask)+ sz[1]*sz[2]*i ])
        ;print, edgeval
        cube[where(badmask)+ sz[1]*sz[2]*i ] = edgeval
        ; set the background to 0 when fftrotating?
        case method of
        'CUBIC': cube_r[*,*,i] = rot(cube[*,*,i]-edgeval,  -rotangle_d ,cubic=-0.5,/interp)+edgeval
        'FFT': cube_r[*,*,i] = fftrot(cube[*,*,i]-edgeval,  rotangle_d)+edgeval
        endcase
    
        cube_r[where(rotmask)+ sz[1]*sz[2]*i ] = !values.f_nan
    endfor


    if keyword_set(stop) then    begin
        ss =  [[[cube]],[[cube_r]]]
        ss = ss[*,*,[0,2,1,3]]
        atv, ss,/bl

        stop
    endif
    backbone->set_keyword, 'HISTORY', "Rotated by "+sigfig(rotangle_d, 4)+" deg to have FOV square",ext_num=0
	pa = backbone->get_keyword('PA')
	; FIXME check that the sign of the PA change is correct here? 
    backbone->set_keyword, "PA", pa-rotangle_d, 'Image is rotated to have FOV=square';/saveComment


    cube=cube_r

	if keyword_set(crop) then begin
		cube = cube[48:233, 47:232, *]
		backbone->set_keyword, 'HISTORY', "Cropped to square FOV only"
	endif





	; FIXME verify that the following are OK?
    ;--- Update FITS header information here. --
    ; Only modify parameters which we have just changed!
    ;
    ; Some notes on angle conventions for WCS:
    ; The rotation angle below needs to be the angle for how much the image's Y
    ; axis was rotated with respect to north. This is termed the 'Vertical
    ; angle'; see http://www.ucolick.org/~sla/deimos/swpdr/va.html
    ;
    ; The rotation matrix here is used to convert from IMAGE coords to SKY
    ; coords. Hence the sense of the rotation is opposite the PA.
    pixelscale = 0.014
    ; rotation matrix.
    ;
    ; TODO: figure out whether the image is SKY RIGHT or SKY LEFT
    ;  i.e. where's east??
    pc = [[cos(-rotangle_d*!dtor), -sin(-rotangle_d*!dtor)], $
          [sin(-rotangle_d*!dtor), cos(-rotangle_d*!dtor)]]

    ra = backbone->get_keyword("RA") 
    dec = backbone->get_keyword("dec") 

;    sxaddhist, /comment, "  For specification of Stokes WCS axis, see ", hdr
;    sxaddhist, /comment, "  Greisen & Calabretta 2002 A&A 395, 1061, section 5.4", hdr
;
;    sxaddpar, hdr, "FILETYPE", "Stokes Cube", "What kind of IFS file is this?"
;    sxaddpar, hdr, "WCSAXES", 3, "Number of axes in WCS system"
;    sxaddpar, hdr, "CTYPE1", "RA---TAN","Right Ascension."
;    sxaddpar, hdr, "CTYPE2", "DEC--TAN","Declination."
;    sxaddpar, hdr, "CTYPE3", "STOKES",     "Polarization"
;    sxaddpar, hdr, "CUNIT1", "deg",  "R.A. unit is degrees, always"
;    sxaddpar, hdr, "CUNIT2", "deg",  "Declination unit is degrees, always"
;    sxaddpar, hdr, "CUNIT3", "N/A",       "Polarizations"
    sz = size(cube)
    backbone->set_keyword, "NAXIS1", sz[1], ext_num=1
    backbone->set_keyword, "NAXIS2", sz[2], ext_num=1
    backbone->set_keyword, "CRVAL1", ra, "R.A. at reference pixel"
    backbone->set_keyword, "CRVAL2", dec, "Declination at reference pixel"
;    backbone->set_keyword, "CRVAL3", -6, " Stokes axis: image 0 is Y parallel, 1 is X parallel "
    ; need to add 1 here to account for "IRAF/FITS" 1-based convention used for
    ; WCS coordinates
    backbone->set_keyword, "CRPIX1", xcen+1,         "Reference pixel location"
    backbone->set_keyword, "CRPIX2", ycen+1,         "Reference pixel location"
;    backbone->set_keyword, "CRPIX3", 0,         "Reference pixel location"
    backbone->set_keyword, "CDELT1", pixelscale/3600., "Pixel scale is "+sigfig(pixelscale,2)+" arcsec/pixel"
    backbone->set_keyword, "CDELT2", pixelscale/3600., "Pixel scale is "+sigfig(pixelscale,2)+" arcsec/pixel"
;    backbone->set_keyword, "CDELT3", 1, "Stokes axis: image 0 is Y parallel, 1 is X parallel"

    backbone->set_keyword, "PC1_1", pc[0,0], "RA, Dec axes rotated by "+sigfig(rotangle_d,4)+" degr."
    backbone->set_keyword, "PC1_2", pc[0,1], "RA, Dec axes rotated by "+sigfig(rotangle_d,4)+" degr."
    backbone->set_keyword, "PC2_1", pc[1,0], "RA, Dec axes rotated by "+sigfig(rotangle_d,4)+" degr."
    backbone->set_keyword, "PC2_2", pc[1,1], "RA, Dec axes rotated by "+sigfig(rotangle_d,4)+" degr."
;    sxaddpar, hdr, "PC3_3", 1, "Stokes axis is unrotated"
    ; TODO WCS paper III suggests adding MJD-AVG to specify midpoint of
    ; observations for conversions to barycentric.
;    sxaddpar, hdr, "RADESYS", "FK5", "RA and Dec are in FK5"
;    sxaddpar, hdr, "EQUINOX", 2000.0, "RA, Dec equinox is J2000"
;



    *(dataset.currframe[0])=cube
    
@__end_primitive

end


      program process_cql3d_output

! (DBB 3/4/2020)
! Copied coding from LH section to EC section which interpolates CQL3D grid onto Plasma 
! State grid for ps%peech and ps%curech.

! (DBB 3/2/2020)
! Removed code that hardwired "cql3d.nc" as the cql3d output file name.  Inserted coding
! to get cql3d_output_file from a command line argument.

! (DBB 4/4/2019)
! Added check to see if ImChizz.inp_template exists (i.e. input file for subroutine 
! write_inchizz_inp).  Needed so this code can be used TORLH which needs ImChizz.inp
! or with other codes which don't use ImChizz.inp. 
!
! Modified to produce namelist needed by imchzz code (DBB and JL 5/9/2017)
! The way this is done is to call a contained subroutine write_inchizz_inp which writes the
! file.  The write_inchizz_inp subroutine uses the ImChizzrel_mod.F90 module, to read the
! namelists in a template ImChizz.inp file.  It takes the toroidal and poloidal fluxes 
! from the plasma state and inserts them into the namelist variables rho_tor = ps%rho and
! rho_pol = sqrt(ps%psipol)/.
! 


!--------------------------------------------------------------------
! process_cql3d_output, BH 08/12/2012
! based on
! lab--June 2, 2010,, process_fp_rfmin_cql3d_output.f, 
! BobH, process_genray_ouput.f90, /06/13/2008
! Long-Poe Ku, 02/13/08, mods for PS2.
! BobH, 03/28/07        based on Berry  process_aorsa_output
! Lee A. Berry 12/6/06  based on D. McMcune's test program
!--------------------------------------------------------------------
!
! This program reads rf current and power deposition profiles
! from a output netcdf file, mnemonic.nc, generated by the cql3d fp
! code, and transfers this data to the plasma state (PS) module.
! In general, the necessary PS storage will have already been set up by
! prepare_genray_input.f90/other rf prep, or by prepare_cql3d_input.f90.
! 
!     process_cql3d_output takes 2 command line arguments:
!                  1st: cql3d_output, gives types of output power 
!                       depostion and currents
!                       (One of 'LH', 'EC' 'IC' 'NBI' 'RW' 
!                       'LH+RW' 'NBI+IC').
!                       (Plasma state component RW refers to RunaWay elec.)
!                       Present implementation is 'LH', 'EC', 'IC', 'NBI', 
!                       'RW', 'LH+RW'.  
!                       (Future: dimension cql3d_output
!                       and add number of elements to treat simultaneously.)
!                  2nd: cql3d_output_file is file name of cql3d netcdf output file. 
!                       It was previously hard wired to "cql3d.nc".  It is set in
!                       the cql3d input file, namelist "setup" 
! 

! define state object and interface...

      USE plasma_state_mod
!--------------------------------------------------------------------------

      use swim_global_data_mod, only :
     1 rspec, ispec,                  ! int: kind specification for real 
                                      !and integer
!!            & swim_string_length, & ! length of strings for names, files, etc.
     1 swim_error                     ! error routine
    

    
!--------------------------------------------------------------------------
!
!   Data declarations
!
!---------------------------------------------------------------------

!--------------------------------------------------------------------------
!
!   AORSA data that will be given to the state via the swim_out file
!   the aorsa output data is in a file called swim_out
!
!--------------------------------------------------------------------------
   

!BH070328:  Begin by reading in toroidal current density from cql3d
!           output netcdf file (mnemonic.nc) and putting it into the state

 
      implicit none

      include 'netcdf.inc'
    
      integer, parameter :: swim_string_length = 256 !for compatibility LAB
      integer :: nnoderho, r0dim, vid_
      integer :: iarg

!     Storage for cql3d netcdf file elements and retrieval
!     Do ncdump on an cql3d netCDF output file to get documentation
      real*8, allocatable, dimension(:)   :: rya   ! radial grid--bin centers
      ! note that mesh in not uniform
      real*8, allocatable, dimension(:)   :: darea,dvol   ! bin areas/volumes   
      real*8, allocatable, dimension(:,:) :: wperp   !perp energy/particle
                                                      !tdim, rdim
      real*8, allocatable, dimension(:,:) :: wpar    !par energy/particle
                                                      !tdim, rdim
      real*8, allocatable, dimension(:,:,:) :: density !density of all species
                                                      !tdim, r0dim, species dim
      real*8, allocatable, dimension(:,:,:) :: temp !temperature of all species
                                                      !tdim, r0dim, species dim
      real*8, allocatable, dimension(:,:,:,:) :: powers !collection of power flows

      !dimensions tdim,rdim/r0dim
      real*8, allocatable, dimension(:,:) :: curtor  !just printout for now
      real*8, allocatable, dimension(:,:) :: ccurtor !just printout for now
      real*8, allocatable, dimension(:,:) :: denra
      real*8, allocatable, dimension(:,:) :: curra
      real*8, allocatable, dimension(:,:) :: elecfld ! added by ptb
      real*8, allocatable, dimension(:,:) :: curr, sptzrp, rovsc ! added by ptb
      real*8, allocatable, dimension(:)   :: tmp_prof, rho_cql   ! added by ptb
      real*8 :: powerlh, currlh, powerlh_int, currlh_int ! added by ptb:
      real*8 :: powerec, currec, powerec_int, currec_int ! added by DBB:
      logical :: nonorm

      !dimensions tdim,nmodsdim,rdim
      real*8, allocatable, dimension(:,:,:) :: powrf,powrfc,powrfl
      real*8, allocatable, dimension(:,:) :: powrft   !tdim,rdim
      character*8 radcoord
      integer :: l

      integer :: ncid,vid,istatus
      integer :: start(2),count(2)
      integer :: start_3(3), count_3(3)
      integer :: start_4(4), count_4(4)
      integer :: nt_id,lrz_id   !Time step dim id, radial fp bins id
      integer :: ngen_id, ntotal_id        !number of general species id
      integer :: nmodsdim_id                  !number of rf modes id
      integer :: nt,lrz,ngen,ntotal,nmods  !values for number of time slices,
            !radial bins,general species , total number of species, rf modes
      integer :: r0dim_id, rdim
      character*256 ::  cur_state_file, cql3d_output_file
      character*8 cql3d_output
      logical :: file_exists

!------------------------------------
!  local
      INTEGER :: ierr
      INTEGER :: iout = 6


      
! ptb:      cur_state_file='/cur_state.cdf'
      cur_state_file='./cur_state.cdf'
      
! ptb:      cql3d_output_file="./mnemonic.nc"  !Set up by cql3d/fp_cql3d.py
!      cql3d_output_file="./cql3d.nc"  !Set up by cql3d/fp_cql3d.py
!      cql3d_output='LH'
cBH131016:  Note: evidently, must have mnemonic='cql3d' in the cqlinput
cBH131016:  file used by cql3d.  
cBH131016:  Note also:  Why is cql3d_output specified here, when
cBH131016:  are forced to give 1 argument below at line 155?

c-----------------------------------------------------------------------
c     Caveats
c-----------------------------------------------------------------------
 
      write(*,*)
      write(*,*)'******************************************************'
      write(*,*)'  BH:'
      write(*,*)'  Aug. 14, 2012:  process_cql3d_output set up mainly'
      write(*,*)'  Aug. 14, 2012:  for EC, LH and RW calcs at this time'
      write(*,*)'  Aug. 14, 2012:  rfmin_fp_cql3d is modified from prev'
      write(*,*)'  Aug. 14, 2012:  LAB coding.'
      write(*,*)'  Aug. 14, 2012:  Structure is in place so further'
      write(*,*)'  Aug. 14, 2012:  apps are readily added (hopefully)'
      write(*,*)'******************************************************'
      write(*,*)



c-----------------------------------------------------------------------
c     Get/setup command line arguments
c-----------------------------------------------------------------------

c F2003 syntax      iargs=command_argument_count()
c Here, use portlib routines (also used by PS module)
      call get_arg_count(iarg)
      if(iarg .ne.2) then 
         print*, 'usage: process_cql3d_output: '
         print*, 'Two command line arguments required: ql3d_output, cql3d_output_file'
     	 stop 1
      end if
c F2003-syntax call get_command_argument(1,cql3d_output)
      call get_arg(1, cql3d_output)
      write(*,*)  'cql3d_output = ', trim(cql3d_output)
      call get_arg(2, cql3d_output_file)
      write(*,*)  'cql3d_output_file = ', trim(cql3d_output_file)


! this call retrieves the plasma state at the present ps%, and
! previous time steps psp%, plus sets storage for the variables.
! plasma state assumed name cur_state.cdf
      CALL ps_get_plasma_state(ierr, trim(cur_state_file))
      if(ierr.ne.0) then
         write(iout,*)'process_cql3d_output: ps_get_plasma_state: ierr='
     +                 ,ierr
         stop 2
      end if
      
   

!.......................................................................
!     Open cql3d netcdf file
!.......................................................................

      istatus = nf_open(trim(cql3d_output_file),nf_nowrite,ncid)
      write(*,*)'after nf_open ncid=',ncid,'istatus',istatus

!     read in dimension IDs
!     we need the time, radial, and species dimensions
      istatus = nf_inq_dimid(ncid,'rdim',lrz_id)
      write(*,*)'after ncdid lrz_id',lrz_id,'istatus',istatus

      istatus = nf_inq_dimid(ncid,'tdim',nt_id)
      write(*,*)'after ncdid nt_id',nt_id,'istatus',istatus
      
      istatus = nf_inq_dimid(ncid,'gen_species_dim',ngen_id)
       write(*,*)'after ncdid ngen_id',ngen_id,'istatus',istatus
      
      istatus = nf_inq_dimid(ncid,'species_dim',ntotal_id)
      write(*,*)'after ncdid ntotal_id',ntotal_id,'istatus',istatus
      
      istatus =  nf_inq_dimid(ncid,'r0dim',r0dim_id)
      write(*,*)'proc_cql3d_op:after ncdid r0dim_id',r0dim_id,'istatus',istatus
      
! ptb:      istatus =  nf_inq_dimid(ncid,'nmods',r0dim_id)
      istatus =  nf_inq_dimid(ncid,'nmodsdim',nmodsdim_id)
      write(*,*)'proc_cql3d_op:after ncdid nmodsdim_id',nmodsdim_id,'istatus',istatus
      
      
      ! first the radial dimension
      ! the first dimension is for bin centers
      
      istatus = nf_inq_dimlen(ncid, lrz_id, lrz)
      write(*,*)'proc_cql3d_op: after ncdinq, # of rad bins= ',lrz,
     1     '  istatus=',istatus      ! the first dimension is for bin centers
      
      ! ptb: added this
      ! next get the number of rf modes - nmods
      istatus = nf_inq_dimlen(ncid, nmodsdim_id, nmods)
      write(*,*)'proc_cql3d_op: after ncdinq, # of rf modes = ',nmods,
     1     '  istatus=',istatus
      ! ptb: added this
      
      ! and the second radial dimension
      ! the second has bin edges, and is the rho_icrf grid
      istatus = nf_inq_dimlen(ncid, r0dim_id, r0dim)
! ptb:      write(*,*)'proc_cql3d_op: after ncdinq, # of rad bins= ',lrz,
      write(*,*)'proc_cql3d_op: after ncdinq, # of rad bins= ',r0dim,
     1     '  istatus=',istatus
      ! check if they are the same, if not more code is needed--grid
      ! subset is used for  solutions
      
      if(lrz .ne. r0dim) then
         print*, 'grid subset used for solutions'
         print*, 'another day, another time'
         stop 1
      end if
     
      ! the time dimension (will always use the last)
      istatus = nf_inq_dimlen(ncid, nt_id, nt)
      write(*,*)'proc_cql3d_op: after ncdinq, # of t steps = ',nt,
     1     '  istatus=',istatus
      
      ! third the number of general species (will be one for now)

      !call ncdinq(ncid, ngen_id,'gen_species_dim', ngen, istatus)
      istatus = nf_inq_dimlen(ncid, ngen_id, ngen)
      write(*,*)'proc_cql3d_op: after ncdinq, #  gen specs = ', ngen,
     1     '  istatus=',istatus
    
!.......................................................................
!     inquire about dimension sizes:time steps,grid size,#species---
!.......................................................................




      ! fourth the number of total species (will be 1 (general) + 1 
      ! duplicate max + thermal + electron in the CMOD order for now)

      istatus = nf_inq_dimlen(ncid, ntotal_id, ntotal)
      write(*,*)'proc_cql3d_op: after ncdinq, #  species FP  = ',ngen,
     1     '  istatus=',istatus
      write(*,*)'proc_cql3d_op: after ncdinq, #  species total = ',
     1    ntotal, '  istatus=',istatus

      if (ngen.ne.1) then
         write(*,*)
         write(*,*)'STOP:Need to check/modify code for ngen.ne.1'
         write(*,*)'    :Probably only few mods needed'
         stop
      endif

      write(*,*)'proc_cql3d_op: after ncdinq, #  species FP  = ',ngen,
     1     '  istatus=',istatus
      write(*,*)'proc_cql3d_op: after ncdinq, #  species total = ',
     1    ntotal, '  istatus=',istatus



!     allocate space for arrays to be read
      allocate (rya(lrz))  !the radial grid
      allocate (density(ntotal,lrz,nt))  !the density
      allocate (temp(ntotal,lrz,nt))  !the temperature
      allocate (darea(lrz),dvol(lrz))
c      allocate (powers(lrz, 13, ntotal, nt))  !Fix, 120813 of proc_rfmin_fp
      allocate (powers(lrz, 13, ngen, nt))  
      allocate (wperp(lrz,nt),wpar(lrz,nt))

      allocate (curtor(lrz,nt))
      allocate (ccurtor(lrz,nt))
      allocate (denra(lrz,nt))   !for rw cases
      allocate (curra(lrz,nt))   !for rw cases
      allocate (curr(lrz,nt))   !for rw cases
      allocate (rovsc(lrz,nt)) ! added by ptb
      allocate (sptzrp(lrz,nt)) ! added by ptb
      allocate (elecfld(lrz+1,nt))  ! added by ptb

      allocate (powrf(lrz,nmods,nt))
      allocate (powrfc(lrz,nmods,nt))
      allocate (powrfl(lrz,nmods,nt))
      allocate (powrft(lrz,nt))
      allocate (tmp_prof(lrz))
      allocate (rho_cql(lrz+1))

!     Specify reading ranges
      start(1:2)=1
      count(1)=lrz
      count(2)=nt

      start_3=1
      count_3(1)=lrz
      count_3(2)=nmods
      count_3(1)=nt
      
      start_4 = 1
      count_4(1) = lrz
      count_4(2) = 13
      count_4(3) = ngen
      count_4(4) = nt
      write(*,*) 'lrz = ', lrz
      write(*,*) 'nmods = ', nmods
      write(*,*) 'nt = ', nt

!.......................................................................
!     read netcdf variables
!.......................................................................
!     will need grid, volumes, powers, wpar, wperp, density

!     Read radial coord type, to check it is sqrt(tor flux)
! ptb      vid = ncvid(ncid,'radcoord',istatus)   !radial coord type
! ptb      call ncvgt(ncid,vid,1,1,radcoord,istatus)
      istatus = nf_inq_varid(ncid, 'radcoord', vid)
      istatus = nf_get_var_text(ncid, vid, radcoord)
      if (radcoord.ne.'sqtorflx') then
         write(*,*)'STOP: problem with cql3d radial coord type, not sqtorflx'
         stop
      endif
      ! the grid
      istatus = nf_inq_varid(ncid, 'rya', vid)
      istatus = nf_get_var_double(ncid, vid, rya)
      write(*,*)'proc_cql3d_op: after ncvgt, rya = ',rya
 
      ! the density
      istatus = nf_inq_varid(ncid, 'density', vid)
      istatus = nf_get_var_double(ncid, vid, density)
      write(*,*)'proc_cql3d_op: after ncvgt, density = ',density
      
       ! the temperature
      istatus = nf_inq_varid(ncid, 'temp', vid)
      istatus = nf_get_var_double(ncid, vid, temp)
      write(*,*)'proc_cql3d_op: after ncvgt, temp = ',temp
      
      ! the bin pol cross-section areas
      istatus = nf_inq_varid(ncid, 'darea', vid)
      istatus = nf_get_var_double(ncid, vid, darea)
      write(*,*)'proc_cql3d_op: after ncvgt, darea = ',darea
 
      ! the bin volumes
      istatus = nf_inq_varid(ncid, 'dvol', vid)
      istatus = nf_get_var_double(ncid, vid, dvol)
      write(*,*)'proc_cql3d_op: after ncvgt, dvol = ',dvol
 
      ! the powers 
      istatus = nf_inq_varid(ncid, 'powers', vid)            
      istatus = nf_get_var_double(ncid, vid, powers)
      write(*,*)'proc_cql3d_op: after ncvgt, powers(e,i) = ',
     1    powers(:, 1:2,  1, nt)
 
      
      ! the energies wperp--wpar
      print*, 'shape of wperp ', shape(wperp)  
      istatus = nf_inq_varid(ncid, 'wperp', vid)
      istatus = nf_get_var_double(ncid, vid, wperp)
      print*, 'shape of wperp ', shape(wperp)            
      write(*,*)'proc_cql3d_op: after ncvgt, wperp = ',
     1    wperp(:, nt)
 
      istatus = nf_inq_varid(ncid, 'wpar', vid)
      istatus = nf_get_var_double(ncid, vid, wpar)           
      write(*,*)'proc_cql3d_op: after ncvgt, wpar = ',
     1    wpar(:, nt)

 
      ! current density and radially cumulative current
      !Toroidal current density at min B point
      istatus = nf_inq_varid(ncid, 'curtor', vid)
      istatus = nf_get_var_double(ncid, vid, curtor)
      !Integrated toroidal current density
      !FSA tor current = (ccurtor(l)-ccurtor(l-1))/darea(l)
      !  (Not presently used)
      istatus = nf_inq_varid(ncid, 'ccurtor', vid)
      istatus = nf_get_var_double(ncid, vid, ccurtor)
      !FSA Parallel current density [j_ll per pol area]
      istatus = nf_inq_varid(ncid, 'curr', vid)
      istatus = nf_get_var_double(ncid, vid, curr)

      !FSA Parallel electric field 
      istatus = nf_inq_varid(ncid, 'elecfld', vid)
      istatus = nf_get_var_double(ncid, vid, elecfld)

      !FSA Spitzer resistivity with Zeff correction <E_parall*B>/<j_parall*B>
      istatus = nf_inq_varid(ncid, 'sptzrp', vid)
      istatus = nf_get_var_double(ncid, vid, sptzrp)

      !FSA Connor resistivity over Spitzer
      istatus = nf_inq_varid(ncid, 'rovsc', vid)
      istatus = nf_get_var_double(ncid, vid, rovsc)

      !Runaway density and current density
      istatus = nf_inq_varid(ncid, 'denra', vid)
      istatus = nf_get_var_double(ncid, vid, denra)
      istatus = nf_inq_varid(ncid, 'curra', vid)
      istatus = nf_get_var_double(ncid, vid, curra)


!     From urfdamp0.f (cql3d):
!     powrf(lr,krf) is the sum of urf power deposited from each mode
!     (or harmonic for nharms.gt.1) in each radial bin, divided
!     by bin volume. (watts/cm**3).  
!
!     powrfc(lr,krf) collisional power/volume (watts/cm**3).      
!
!     powrfl(lr,krf) additional linear power/volume (watts/cm**3).
!
!     powrft(lr,nt) power per volume (watts/cm**3) summed over modes
!     or harmonics, due to urf, collisional and add. linear abs.,
!     at last time step in cql3d simulation.
      !istatus = nf_inq_varid(ncid, 'powrf', vid)   ! no longer exist in cql3d netcdf output
      !istatus = nf_get_var_double(ncid, vid, powrf)
      !istatus = nf_inq_varid(ncid, 'powrfc', vid)
      !istatus = nf_get_var_double(ncid, vid, powrfc)
      !istatus = nf_inq_varid(ncid, 'powrfl', vid)
      !istatus = nf_get_var_double(ncid, vid, powrfl)
      !istatus = nf_inq_varid(ncid, 'powrft', vid)
      !istatus = nf_get_var_double(ncid, vid, powrft)

      if (cql3d_output.eq.'EC') then
      !Here we assume simple cql3d calc of ec current, with no
      !toroidal electric field (or with total tor current w Efld).
      !If we want ec+dc_synergy_current, will need to make two
      !cql3d runs, giving two .nc files, and subtract the two
      !total current densities thus giving ec+ synergy.
      !(Similarly, for other rf-electron cases.)

!DBB Interpolation of ECH power and driven current from CQL3D grid to Plasma State grid.
!    There are comments below in the Lower Hybrid section which also apply here since this
!    is lifted from that coding.

         do l=1,lrz-1
            rho_cql(l+1) = 0.5*(rya(l)+rya(l+1))
         enddo
         rho_cql(1) = 0.0
         rho_cql(lrz+1) = 1.0
         !tmp_prof(1:lrz) = powrft(:,nt) * dvol(:)
         tmp_prof(1:lrz) = powers(:,5,1,nt) * dvol(:)

         write(*,*) 'ps%rho_ecrf = ', ps%rho_ecrf
         write(*,*) 'rho_cql = ', rho_cql
         write(*,*) 'tmp_prof = ', tmp_prof
         write(*,*) 'ps%peech = ', ps%peech
         
         call ps_user_rezone1(rho_cql, ps%rho_ecrf, tmp_prof, 
     &        ps%peech, ierr, nonorm = .TRUE., zonesmoo = .TRUE.)

         if(ierr .ne. 0) stop 'error interpolating CQL3D powers onto PS Grid ps%nrho_ecrf and ps%peech'
         ps%peech_src(:,1) = ps%peech(:)
         write(*,*) 'elecfld(l,nt) = ', elecfld(1:lrz+1,nt)
  
         do l=1,lrz
          tmp_prof(l) = curr(l,nt)
!          tmp_prof(l) = (curr(l,nt) - elecfld(l+1,nt)/
!      &       (rovsc(l,nt)*sptzrp(l,nt)*9.0E+11)) * darea(l)
         enddo
         
         write(*,*) 'curr(l,nt) = ', curr(:,nt)
         write(*,*) 'tmp_prof = ', tmp_prof(:)

         call ps_user_rezone1(rho_cql, ps%rho_ecrf, tmp_prof, 
     &        ps%curech, ierr, nonorm = .TRUE., zonesmoo = .TRUE.)

         write(*,*) 'rezoned ps%curech = ', ps%curech

         if(ierr .ne. 0) stop 'error interpolating CQL3D powrft onto PS Grid ps%nrho_ecrf and ps%curech'

         ps%curech_src(:,1) = ps%curech(:)

! Interpolation of current
         powerec = 0.0
         currec = 0.0
      do l=1,lrz
         powerec = powerec + powrft(l,nt)*dvol(l)
         currec = curr(l,nt)
!          currec = (curr(l,nt) - elecfld(l+1,nt)/
!      &       (rovsc(l,nt)*sptzrp(l,nt)*9.0E+11)) * darea(l) + currec
      enddo
! ptb checking interpolated quantities
         powerec_int = 0.0
         currec_int = 0.0
      do l=1,ps%nrho_ecrf-1
         powerec_int = powerec_int + ps%peech(l)
         currec_int = currec_int + ps%curech(l)
      enddo
      write(*,*) 'power_ec = ', powerec, 'currec = ', currec
      write(*,*) 'power_ec_int = ', powerec_int, 'currec_int = ', currec_int
         
      endif  !On cql3d_output.eq.'EC'


       if (cql3d_output.eq.'LH') then

! ptb Need to map powrft and curr from the cql3d radial grid (rya) to the 
! pelh, pelh_srfc, curlh, and curlh_src radial grid (rho_lhrf) which was set 
! in genray. Assume only one source for this operation (for now).
!N.B.    size(f_target) = size(rho_target) - 1; this is checked.

         write(*,*) 'Advanced into interpolation of cql3d profiles onto PS grid'
         do l=1,lrz-1
            rho_cql(l+1) = 0.5*(rya(l)+rya(l+1))
         enddo
         rho_cql(1) = 0.0
         rho_cql(lrz+1) = 1.0
         !tmp_prof(1:lrz) = powrft(:,nt) * dvol(:)
         tmp_prof(1:lrz) = powers(:,5,1,nt) * dvol(:)

         write(*,*) 'ps%rho_lhrf = ', ps%rho_lhrf
         write(*,*) 'rho_cql = ', rho_cql
         write(*,*) 'tmp_prof = ', tmp_prof
         write(*,*) 'ps%pelh = ', ps%pelh
         
         call ps_user_rezone1(rho_cql, ps%rho_lhrf, tmp_prof, 
     &        ps%pelh, ierr, nonorm = .TRUE., zonesmoo = .TRUE.)
         if(ierr .ne. 0) stop 'error interpolating CQL3D powers onto PS Grid ps%rho_lhrf and ps%pelh'
         ps%pelh_src(:,1) = ps%pelh(:)
         write(*,*) 'elecfld(l,nt) = ', elecfld(1:lrz+1,nt)

!        Now interpolate the cql3d current density
!N.B.    Remember that TSC and the PS are expecting the LH current (amps /zone) so
!N.B.    that we need to actually take J_LH =  J_// - (E_//) / Eta_neo)
!        J_// (A/cm^2) given by curr(:,nt)
!        E_// (V/cm) given by elecfld(1:lrz+1,nt)
!        Spizter resisvtivity Eta (cgs-s) is given by sptzrp(1:lrz,nt)
!        rovsc(1:lrz,nt) is the (Connor resis. / Spitzer resis.)
!        Eta (cgs-s) = Eta (SI-ohm-m) * [1/9 x 10^(-9)] ->>
!        Eta (SI-ohm-m) = Eta(cgs-s) * [9 x 10^9]
!        Eta (ohm-cm) = Eta(SI-ohm-m) * [9 x 10^11]           
!N.B.    When elecfld is used to compute tmp_prof in the loop below we reference
!N.B.    elecfld(l+1,nt) instead of elecfld(l,nt) because elecfld appears to be
!N.B.    written to the cql3d.nc file with the dimension of r00dim=lrz+1 which
!N.B.    is wrong. It should be written with dimension r0dim=lrz. This causes
!N.B.    the first location in elecfld to be written with a value from the
!N.B.    the namelist setting for iproelec=parabola, which is arbitrarily wrong. 
!N.B.    The correct values that were used in the cql3d calculation are stored in 
!N.B.    elecfld(2:lrz+1).
  
         do l=1,lrz
         tmp_prof(l) = (curr(l,nt) - elecfld(l+1,nt)/
     &       (rovsc(l,nt)*sptzrp(l,nt)*9.0E+11)) * darea(l)
         enddo

         call ps_user_rezone1(rho_cql, ps%rho_lhrf, tmp_prof, 
     &        ps%curlh, ierr, nonorm = .TRUE., zonesmoo = .TRUE.)

         if(ierr .ne. 0) stop 'error interpolating CQL3D powrft onto PS Grid ps%rho_lhrf and ps%curlh'

         ps%curlh_src(:,1) = ps%curlh(:)

!      do l=1,lrz
!         ps%power_lh(l)=powrft(l,nt)*dvol(l)
!         ps%curlh(l)=curr(l,nt)*darea(l) !Might use ccurtor, as above
!      enddo
         powerlh = 0.0
         currlh = 0.0
      do l=1,lrz
         powerlh = powerlh + powrft(l,nt)*dvol(l)
         currlh = (curr(l,nt) - elecfld(l+1,nt)/
     &       (rovsc(l,nt)*sptzrp(l,nt)*9.0E+11)) * darea(l) + currlh
      enddo
! ptb checking interpolated quantities
         powerlh_int = 0.0
         currlh_int = 0.0
      do l=1,ps%nrho_lhrf-1
         powerlh_int = powerlh_int + ps%pelh(l)
         currlh_int = currlh_int + ps%curlh(l)
      enddo
      write(*,*) 'power_lh = ', powerlh, 'currlh = ', currlh
      write(*,*) 'power_lh_int = ', powerlh_int, 'currlh_int = ', currlh_int
! end of ptb diagnostics and hack

      INQUIRE(FILE='ImChizz.inp_template', EXIST=file_exists)
      write (*,*) 'file_exists = ', file_exists
      IF (file_exists .eq. .TRUE.) then
		  WRITE (*,*) "About to call write_inchizz_inp"
		  CALL write_inchizz_inp
	  ENDIF

      endif  !On cql3d_output.eq.'LH'


      if (cql3d_output.eq.'RW') then
      if(ps%nrho_rw.ne.(lrz+1)) then
         write(*,*)'STOP: problem with PS EC setup'
         write(*,*)'ps%nrho_ecrf,(lrz+1)= ',ps%nrho_rw,(lrz+1)
         stop
      endif
      do l=1,lrz
         ps%nrw(l)=denra(l,nt)*1.e6 !Runaway density above ucrit
         ps%cur_rw(l)=curra(l,nt)*darea(l) !Runaway curr/bin above ucrit
      enddo
      ps%dcur_rw_dvloop(1:lrz)=0.0d0   !For now, BH070312: need multiple cql3d
                                     !runs (w fp_cql3d.py).
      endif  !On cql3d_output.eq.'RW'


      if (cql3d_output.eq.'LH+RW') then
      if(ps%nrho_lhrf.ne.(lrz+1)) then
         write(*,*)'STOP: problem with PS LH setup'
         write(*,*)'ps%nrho_lhrf,(lrz+1)= ',ps%nrho_lhrf,(lrz+1)
         stop
      endif
      do l=1,lrz
         ps%power_lh(l)=powrft(l,nt)*dvol(l)
         ps%curlh(l)=curr(l,nt)*darea(l) !Might use ccurtor, as above
      enddo
      if(ps%nrho_rw.ne.(lrz+1)) then
         write(*,*)'STOP: problem with PS RW setup'
         write(*,*)'ps%nrho_rw,(lrz+1)= ',ps%nrho_rw,(lrz+1)
         stop
      endif
      do l=1,lrz
         ps%nrw(l)=denra(l,nt)*1.e6 !Runaway density above ucrit
         ps%cur_rw(l)=curra(l,nt)*darea(l) !Runaway curr/bin above ucrit
      enddo
      ps%dcur_rw_dvloop(1:lrz)=0.0   !For now, BH070312: need multiple cql3d
                                     !runs (w fp_cql3d.py).
      endif  !On cql3d_output.eq.'LH+RW'

      if (cql3d_output.eq. 'NBI' .or. cql3d_output.eq. 'NBI+IC') then
         write(*,*)'process_cql3d_output: stop, not yet setup for NBI'
         stop
      endif  !On cql3d_output.eq.'NBI'


      if (cql3d_output.eq.'IC') then
!     This section taken from Lee Berry process_fp_rfmin_cql3d_output.f
!     and adjusted:
!     Now need to put into state
      ! the general species is in the last -1 of the list
      ! powers(*,1,k,t)=due to collisions with Maxw electrons
      ! k is the number of the general species
      ! nt is the last time slice of the cql3d run
!BH120813      ps%pmine = -dvol * powers(1:ps%nrho_icrf-1,1,ntotal - 1,nt)
      ps%pmine = -dvol * powers(1:ps%nrho_icrf-1,1,1,nt)
      ! powers(*,2,k,t)=due to collisions with Maxw ions
!BH120813      ps%pmini = -dvol * powers(1:ps%nrho_icrf-1,2,ntotal - 1,nt)
      ps%pmini = -dvol * powers(1:ps%nrho_icrf-1,2,1,nt)
      ps%eperp_mini(1,1:ps%nrho_icrf-1) = wperp(1:ps%nrho_icrf-1,nt)
      ps%epll_mini(1,1:ps%nrho_icrf-1) = wpar(1:ps%nrho_icrf-1,nt)

      print*, 'power check on cql'
      print*, 'minority to electron power = ', sum(ps%pmine)
      print*, 'minority to ion power = ', sum(ps%pmini)

      endif   !On cql3d_output.eq.'IC'




!     Close cql3d netCDF file
      call ncclos(ncid,istatus)

      write(iout,*)
     +     'process_cql3d_output: --storing cql3d data in current PS'

!BH:  Two viable PS update methods have been used. Below: use DBB method.
cDBB!--------------------------------------------------------------------
cDBB! Store the data in partial plasma_state file
cDBB!--------------------------------------------------------------------

cBH	  CALL PS_WRITE_UPDATE_FILE('RF_GENRAY_PARTIAL_STATE', ierr)
cBH	  WRITE (*,*) "Stored Partial RF Plasma State"
    
cDBB!     Stores the modified plasma state--doesn't commit it.
cDBB!     The previous one is still around
cDBB      call ps_store_plasma_state(ierr)
cDBB      if(ierr .ne. 0) then
cDBB      write(iout,*)
cDBB     +        'Cannot ps_store_plasma_state in process_genray_output'
cDBB      end if
c
c
cBH???:  How does IPS know name FP_CQL3D_PARTIAL_STATE???
cWael_to_BH:  Only needed here and in fp_cql3d_genray.py, as I understand.
      CALL PS_WRITE_UPDATE_FILE('FP_CQL3D_PARTIAL_STATE', ierr)
      WRITE (*,*) "Stored Partial FP_CQL3D Plasma State"

      contains

	  SUBROUTINE write_inchizz_inp

	  IMPLICIT NONE
	  integer, parameter :: r8 = SELECTED_REAL_KIND(12,100)
      INTEGER, PARAMETER :: LLOWER = 1, UUPPER = 2
	  INTEGER, PARAMETER :: LBOUND = 1, UBOUND = 2
	  INTEGER, PARAMETER :: PSI_DIR = 1, BMOD_DIR = 2, NPAR_DIR = 3
	  INTEGER, PARAMETER :: N_DIR = NPAR_DIR - PSI_DIR + 1, BMOD_INDEX = 4
	  INTEGER, PARAMETER :: SIGN_DIR =  4
      INTEGER, PARAMETER :: Y_DIM = 1, X_DIM = 2, R_DIM = 3
	  INTEGER, PARAMETER :: NF_DIM = R_DIM - Y_DIM + 1
	  INTEGER, PARAMETER :: N_STR = 80
	  INTEGER, PARAMETER :: TE_DIM = 1, NE_DIM = 2, MAXPROF=128
      REAL(r8), PARAMETER :: PI = 3.14159265358979_r8, TWOPI = 6.28318530717958_r8

	  LOGICAL :: output_F_data, output_Chi, mesh_output
	  INTEGER :: npts(PSI_DIR:NPAR_DIR), n_uprp
	  INTEGER, DIMENSION(PSI_DIR:NPAR_DIR) :: n_mesh
	  REAL(r8), DIMENSION(PSI_DIR:NPAR_DIR, LLOWER:UUPPER) :: mesh_limits
	  REAL(r8) :: du_max_min_ratio
	  CHARACTER *(N_STR) :: F_source, shape, cdf_fn, cql3d_cdf_fn, psitable_fn
	  CHARACTER *(1) :: ibq
	  CHARACTER *(N_STR) :: uprp_grid_type, proftype
	  INTEGER :: nF(PSI_DIR:NPAR_DIR)
	  REAL(r8) :: enorm, R_major, a, Btor, frequency, npar, theta, psi
	  REAL(r8), DIMENSION(TE_DIM:NE_DIM) :: p_inner, p_outer, maxx, minn
	  REAL(r8), DIMENSION(Y_DIM:R_DIM) :: lower, upper
	  INTEGER :: RadMapDim
	  REAL(r8), DIMENSION(MAXPROF) :: Teprof, Neprof, rho_pol, rho_tor

!I/O units
      integer :: inp_unit, out_unit, iarg
      logical :: lex

      NAMELIST / ImChizz_nml / F_source, npts, output_F_data, cdf_fn, psitable_fn, ibq
      NAMELIST / Fd_nml / nF, enorm, p_inner, p_outer, maxx, minn,
     1 lower, upper, shape, R_major, a, Btor, frequency, cql3d_cdf_fn,
     2 Teprof, Neprof, proftype, RadMapDim, rho_pol, rho_tor
      NAMELIST / Num_nml / n_uprp, n_mesh, mesh_limits, mesh_output,
     1 uprp_grid_type, du_max_min_ratio

      WRITE (*,*) "Entered write_inchizz_inp"
      
!****************************************************************************************
! Defaults
!****************************************************************************************

      uprp_grid_type = 'uniform'  ! 'uniform' or 'exponential'
      du_max_min_ratio = 1._r8  
    ! max(d_uprp) / min(d_uprp) for an exponential grid

      F_source = 'analytic'  ! 'analytic' or 'cql3d'
      shape = 'Maxwellian'
      proftype = 'parabolic'
      cdf_fn = 'ImChi.cdf'
      psitable_fn = 'Dql_toric.cdf'
      output_F_data = .TRUE.; output_Chi = .TRUE.
      npts = (/ 10, 8, 20 /)

      nF = (/ 5, 16, 100 /)
      enorm = 2500_r8
      p_inner(TE_DIM:NE_DIM) =  2._r8
      p_outer = (/ 2._r8, 1._r8 /)
      lower(Y_DIM:R_DIM) = 0._r8
      upper(Y_DIM:R_DIM) = (/ TWOPI, 1._r8, 1._r8 /)
      minn(TE_DIM:NE_DIM) = (/ .1_r8, 1.E18_r8 /)
      maxx(TE_DIM:NE_DIM) = (/ 4._r8, 1.E19_r8 /)

      R_major = 60._r8; a = 20._r8; Btor = 5._r8; frequency = 4.E9_r8
      cql3d_cdf_fn = 'cql3d.cdf'

      n_uprp = 100  
    ! n_uprp is the number of cells, not the number of nodes 
    ! (which is n_uprp + 1)

      n_mesh(PSI_DIR:NPAR_DIR) = (/ 10, 20, 30 /)
      mesh_limits(PSI_DIR, LLOWER:UUPPER) = (/ 0._r8, 1._r8 /)
      mesh_limits(BMOD_DIR, LLOWER:UUPPER) = (/ 1._r8, 2._r8 /) ! B/B_min
      mesh_limits(NPAR_DIR, LLOWER:UUPPER) = (/ 1.10_r8, 8._r8 /)
      mesh_output = .TRUE.

!****************************************************************************************
! Read template ImChizz.inp
!****************************************************************************************
      call getlun(inp_unit,ierr)  ;  call getlun(out_unit,ierr)
	
      write(*,*) 'Process qcl3d output reading ImChizz.inp_template'
      open(unit=inp_unit, file='ImChizz.inp_template', status='old',
     1 form='formatted')
      INQUIRE(inp_unit, exist=lex)
      IF (lex) THEN
		READ(inp_unit, nml = ImChizz_nml)
		READ(inp_unit, nml = Fd_nml)
		READ(inp_unit, nml = Num_nml)
      ELSE
         write(*,*)
     1     'ImChizz.inp does not exist or there was a read error'
      END IF
      close(inp_unit)

!****************************************************************************************
! Load up data
!****************************************************************************************
	
	  RadMapDim = size(ps%rho_eq)
	  rho_pol = 0.0
	  rho_tor = 0.0
	  rho_pol(1:RadMapDim) = sqrt(ps%psipol / ps%psipol(size(ps%rho_eq)))
	  rho_tor(1:RadMapDim) = ps%rho_eq
	  R_major = ps%R_axis*100.
	  a = 100.*(ps%R_MAX_LCFS - ps%R_MIN_LCFS)/2.
	  Btor = ps%B_axis
	  frequency = ps%freq_lh(1)

!****************************************************************************************
! Write ImChizz.inp
!****************************************************************************************

      open(unit=out_unit, file='ImChizz.inp',
     1 status = 'unknown', form = 'formatted',delim='quote')

      WRITE (*, nml = ImChizz_nml)
      WRITE (*, nml = Fd_nml)
      WRITE (*, nml = Num_nml)

	  WRITE(out_unit, nml = ImChizz_nml)
	  WRITE(out_unit, nml = Fd_nml)
	  WRITE(out_unit, nml = Num_nml)

      close(out_unit)

      RETURN
      END SUBROUTINE write_inchizz_inp


      SUBROUTINE getlun (ilun,ierr)
!
!-----------------------------------------------------------------------
!
! ****** Return an unused logical unit identifier.
!
!-----------------------------------------------------------------------
!
! ****** Upon successful completion (IERR=0), the first
! ****** unused logical unit number between MINLUN and
! ****** MAXLUN, inclusive, is returned in variable ILUN.
! ****** If all units between these limits are busy,
! ****** IERR=1 is returned.
!
!-----------------------------------------------------------------------
!
      INTEGER, INTENT(OUT) :: ilun, ierr
!
!-----------------------------------------------------------------------
!
! ****** Range of valid units.
!
      INTEGER, PARAMETER :: minlun=30, maxlun=99
      LOGICAL :: busy
      INTEGER :: i
!
!-----------------------------------------------------------------------
!
      ierr=0
!
! ****** Find an unused unit number.
!
      DO i=minlun,maxlun
        INQUIRE (unit=i,opened=busy)
        IF (.NOT.busy) THEN
           ilun=1
           RETURN
        END IF
      END DO
!
! ****** Fall through here if all units are busy.
!
      ierr=1
      RETURN

      END subroutine getlun
     
      end program process_cql3d_output

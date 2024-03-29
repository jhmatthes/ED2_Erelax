!==========================================================================================!
!==========================================================================================!
!     This subroutine copies various atmospheric fields that are needed by ED-2.           !
!------------------------------------------------------------------------------------------!
subroutine copy_atm2lsm(ifm,init)
   use ed_state_vars        , only : edgrid_g      & ! structure
                                   , edtype        & ! structure
                                   , polygontype   ! ! structure
   use mem_basic            , only : co2_on        & ! intent(in)
                                   , co2con        & ! intent(in)
                                   , basic_g       ! ! structure
   use mem_radiate          , only : radiate_g     & ! structure
                                   , iswrtyp       ! ! intent(in)
   use mem_cuparm           , only : cuparm_g      ! ! structure
   use mem_micro            , only : micro_g       ! ! structure
   use mem_grid             , only : grid_g        & ! structure
                                   , zt            & ! intent(in)
                                   , dzt           & ! intent(in)
                                   , zm            & ! intent(in)
                                   , if_adap       & ! intent(in)
                                   , jdim          ! ! intent(in)
   use node_mod             , only : master_num    & ! intent(in)
                                   , mmzp          & ! intent(in)
                                   , mmxp          & ! intent(in)
                                   , mmyp          & ! intent(in)
                                   , ia            & ! intent(in)
                                   , iz            & ! intent(in)
                                   , ja            & ! intent(in)
                                   , jz            & ! intent(in)
                                   , ia_1          & ! intent(in)
                                   , iz1           & ! intent(in)
                                   , ja_1          & ! intent(in)
                                   , jz1           ! ! intent(in)
   use rconstants           , only : t3ple         & ! intent(in)
                                   , t00           & ! intent(in)
                                   , wdnsi         ! ! intent(in)
   use ed_node_coms         , only : mynum         ! ! intent(in)
   use mem_edcp             , only : co2_offset    & ! intent(in)
                                   , atm_co2_min   ! ! intent(in)
   use therm_lib            , only : thetaeiv      & ! function
                                   , rehuil        & ! function
                                   , ptrh2rvapil   & ! function
                                   , press2exner   & ! function
                                   , exner2press   & ! function
                                   , extemp2theta  & ! function
                                   , extheta2temp  & ! function
                                   , tl2uint       ! ! function
   use met_driver_coms      , only : imetrad       & ! intent(in)
                                   , rlong_min     & ! intent(in)
                                   , atm_rhv_min   & ! intent(in)
                                   , atm_rhv_max   ! ! intent(in)
   use canopy_radiation_coms, only : fvis_beam_def & ! intent(in)
                                   , fvis_diff_def & ! intent(in)
                                   , fnir_beam_def & ! intent(in)
                                   , fnir_diff_def ! ! intent(in)
   implicit none
   !----- Arguments -----------------------------------------------------------------------!
   integer                             , intent(in)  :: ifm
   logical                             , intent(in)  :: init
   !----- Local variables -----------------------------------------------------------------!
   type(edtype)                        , pointer     :: cgrid
   type(polygontype)                   , pointer     :: cpoly 
   integer                                           :: ipy
   integer                                           :: isi
   integer                                           :: ipa
   integer                                           :: m1
   integer                                           :: m2
   integer                                           :: m3
   integer                                           :: m1max
   integer                                           :: ix
   integer                                           :: iy
   integer                                           :: i
   integer                                           :: j
   integer                                           :: n
   integer                                           :: k1w
   integer                                           :: k2w
   integer                                           :: k3w
   integer                                           :: k2u
   integer                                           :: k3u
   integer                                           :: k2u_1
   integer                                           :: k3u_1
   integer                                           :: k2v
   integer                                           :: k3v
   integer                                           :: k2v_1
   integer                                           :: k3v_1
   real             , dimension(:,:)   , allocatable :: rshortd
   real             , dimension(:,:)   , allocatable :: par_beam
   real             , dimension(:,:)   , allocatable :: par_diff
   real             , dimension(:,:)   , allocatable :: nir_beam
   real             , dimension(:,:)   , allocatable :: nir_diff
   real             , dimension(:,:)   , allocatable :: up_mean
   real             , dimension(:,:)   , allocatable :: vp_mean
   real             , dimension(:,:)   , allocatable :: pi0_mean
   real             , dimension(:,:)   , allocatable :: rv_mean
   real             , dimension(:,:)   , allocatable :: rtp_mean
   real             , dimension(:,:)   , allocatable :: theta_mean
   real             , dimension(:,:)   , allocatable :: co2p_mean
   real                                              :: scalar1
   real                                              :: topma_t
   real                                              :: wtw
   real                                              :: wtu1
   real                                              :: wtu2
   real                                              :: wtv1
   real                                              :: wtv2
   real                                              :: relhum
   real                                              :: rvaux
   real                                              :: fice
   real                                              :: snden
   real                                              :: press
   !---------------------------------------------------------------------------------------!
  
   !----- Assigning some aliases. ---------------------------------------------------------!
   m2    =  mmxp(ifm)
   m3    =  mmyp(ifm)
   cgrid => edgrid_g(ifm)

   !----- Allocate the 2-D arrays. --------------------------------------------------------!
   allocate(rshortd    (m2,m3))
   allocate(par_beam   (m2,m3))
   allocate(par_diff   (m2,m3))
   allocate(nir_beam   (m2,m3))
   allocate(nir_diff   (m2,m3))
   allocate(up_mean    (m2,m3))
   allocate(vp_mean    (m2,m3))
   allocate(pi0_mean   (m2,m3))
   allocate(rv_mean    (m2,m3))
   allocate(rtp_mean   (m2,m3))
   allocate(theta_mean (m2,m3))
   allocate(co2p_mean  (m2,m3))

   up_mean    = 0.0
   vp_mean    = 0.0
   pi0_mean   = 0.0
   rv_mean    = 0.0
   rtp_mean   = 0.0
   theta_mean = 0.0


   !---------------------------------------------------------------------------------------!
   !    Loop over the grid points, and prepare the atm data fields.  First, check which    !
   ! vertical coordinate we are using.                                                     !
   !---------------------------------------------------------------------------------------!
   select case (if_adap)
   case (0) 
      !------------------------------------------------------------------------------------!
      !      Terrain-following coordinate (sigma_z).  Here we simply use the lowest pre-   !
      ! dicted level for thermo and wind variables, and a simple average between levels    !
      ! one and two for Exner function and density.  I am not sure this is consistent with !
      ! what is done for density in adaptive coordinate...                                 !
      !------------------------------------------------------------------------------------!
      do j=ja,jz
         do i=ia,iz
            theta_mean(i,j) = basic_g(ifm)%theta(2,i,j)
            rv_mean(i,j)    = basic_g(ifm)%rv(2,i,j)
            rtp_mean(i,j)   = basic_g(ifm)%rtp(2,i,j)
            up_mean(i,j)    = (basic_g(ifm)%up(2,i,j) + basic_g(ifm)%up(2,i-1,j)) * 0.5
            vp_mean(i,j)    = (basic_g(ifm)%vp(2,i,j) + basic_g(ifm)% vp(2,i,j-jdim)) * 0.5
            pi0_mean(i,j)   = ( basic_g(ifm)%pp(1,i,j) + basic_g(ifm)%pp(2,i,j)            &
                              + basic_g(ifm)%pi0(1,i,j)+basic_g(ifm)%pi0(2,i,j)) * 0.5
            if (co2_on) then
               co2p_mean(i,j) = basic_g(ifm)%co2p(2,i,j)
            else
               co2p_mean(i,j) = co2con(1)
            end if
            if (iswrtyp == 3) then
               !----- We obtain the diffuse radiation straight from Harrington. -----------!
               rshortd(i,j)  = radiate_g(ifm)%rshort_diffuse(i,j)
               nir_beam(i,j) = fnir_beam_def * (radiate_g(ifm)%rshort(i,j)-rshortd(i,j))
               nir_diff(i,j) = fnir_diff_def * rshortd(i,j)
               par_beam(i,j) = fvis_beam_def * (radiate_g(ifm)%rshort(i,j)-rshortd(i,j))
               par_diff(i,j) = fvis_diff_def * rshortd(i,j)

            else
               !---------------------------------------------------------------------------!
               !      The following subroutine estimates the diffuse shortwave radiation.  !
               ! This is a gross approximation that uses constant scattering coefficients. !
               !---------------------------------------------------------------------------!
               select case (imetrad)
               case (0,1)
                  call short2diff_sib(radiate_g(ifm)%rshort(i,j),radiate_g(ifm)%cosz(i,j)  &
                                     ,rshortd(i,j))
                  nir_beam(i,j) = fnir_beam_def * (radiate_g(ifm)%rshort(i,j)-rshortd(i,j))
                  nir_diff(i,j) = fnir_diff_def * rshortd(i,j)
                  par_beam(i,j) = fvis_beam_def * (radiate_g(ifm)%rshort(i,j)-rshortd(i,j))
                  par_diff(i,j) = fvis_diff_def * rshortd(i,j)
               case (2)
                  press = exner2press(pi0_mean(i,j))

                  call short_bdown_weissnorman(radiate_g(ifm)%rshort_diffuse(i,j),press    &
                                              ,radiate_g(ifm)%cosz(i,j),par_beam(i,j)      &
                                              ,par_diff(i,j),nir_beam(i,j),nir_diff(i,j)   &
                                              ,rshortd(i,j) )
               end select
            end if
         end do
      end do
   case (1)
      !------------------------------------------------------------------------------------!
      !     Adaptive height coordinate (shaved-eta).  Here we need to do a weighted aver-  !
      ! age using the lowest predicted points and the points avove them.                   !
      !------------------------------------------------------------------------------------!
      do j=ja,jz
         do i=ia,iz
            !------------------------------------------------------------------------------!
            !    Finding the lowest boundary levels, depending on which kind of variable   !
            ! we are averaging (staggered grid).                                           !
            !------------------------------------------------------------------------------!
            !----- U points, need to average between i-1 and i... -------------------------!
            k2u   = nint(grid_g(ifm)%flpu(i,j))
            k3u   = k2u + 1
            k2u_1 = nint(grid_g(ifm)%flpu(i-1,j))
            k3u_1 = k2u_1 + 1
            !----- V points, need to average between j-jdim and j... ----------------------!
            k2v   = nint(grid_g(ifm)%flpv(i,j))
            k3v   = k2v+1
            k2v_1 = nint(grid_g(ifm)%flpv(i,j-jdim))
            k3v_1 = k2v_1 + 1
            !----- W/T points, only the i,j points are needed...  -------------------------!
            k2w   = nint(grid_g(ifm)%flpw(i,j))
            k1w   = k2w - 1
            k3w   = k2w + 1
            !------------------------------------------------------------------------------!

            topma_t = .25 * ( grid_g(ifm)%topma(i,j) + grid_g(ifm)%topma(i-1,j)            &
                            + grid_g(ifm)%topma(i,j-jdim) + grid_g(ifm)%topma(i-1,j-jdim))

            !------------------------------------------------------------------------------!
            !     Computing the weights for lowest predicted points, relative to points    !
            ! above them.                                                                  !
            !------------------------------------------------------------------------------!
            wtw  = (zm(k2w) - topma_t) * dzt(k2w)
            wtu1 = grid_g(ifm)%aru(k2u_1,i-1,j)    / grid_g(ifm)%aru(k3u_1,i-1,j)
            wtu2 = grid_g(ifm)%aru(k2u,i,j)        / grid_g(ifm)%aru(k3u,i,j)
            wtv1 = grid_g(ifm)%arv(k2v_1,i,j-jdim) / grid_g(ifm)%arv(k3v_1,i,j-jdim)
            wtv2 = grid_g(ifm)%arv(k2v,i,j)        / grid_g(ifm)%arv(k3v,i,j)

            theta_mean(i,j)   =       wtw   * basic_g(ifm)%theta(k2w,i,j)                  &
                              + (1. - wtw)  * basic_g(ifm)%theta(k3w,i,j)

            rv_mean(i,j)      =       wtw   * basic_g(ifm)%rv(k2w,i,j)                     &
                              + (1. - wtw)  * basic_g(ifm)%rv(k3w,i,j)

            rtp_mean(i,j)     =       wtw   * basic_g(ifm)%rtp(k2w,i,j)                    &
                              + (1. - wtw)  * basic_g(ifm)%rtp(k3w,i,j)

            if (co2_on) then
               co2p_mean(i,j) =       wtw   * basic_g(ifm)%co2p(k2w,i,j)                   &
                              + (1. - wtw)  * basic_g(ifm)%co2p(k3w,i,j)
            else
               co2p_mean(i,j) = co2con(1)
            end if

            up_mean(i,j)      = (        wtu1  * basic_g(ifm)%up(k2u_1,i-1,j)              &
                                +  (1. - wtu1) * basic_g(ifm)%up(k3u_1,i-1,j)              &
                                +        wtu2  * basic_g(ifm)%up(k2u,i,j)                  &
                                +  (1. - wtu2) * basic_g(ifm)%up(k3u,i,j)       ) * .5
            vp_mean(i,j)      = (        wtv1  * basic_g(ifm)%vp(k2v_1,i,j-jdim)           &
                                +  (1. - wtv1) * basic_g(ifm)%vp(k3v_1,i,j-jdim)           &
                                +        wtv2  * basic_g(ifm)%vp(k2v,i,j)                  &
                                +  (1. - wtv2) * basic_g(ifm)%vp(k3v,i,j)       ) * .5
            
            !------------------------------------------------------------------------------!
            !     Exner function and density, need to consider the layer beneath the       !
            ! ground to make the profile.                                                  !
            !------------------------------------------------------------------------------!
            if (wtw >= .5) then
               pi0_mean(i,j)  = (wtw - .5)                                                 &
                              * (basic_g(ifm)%pp(k1w,i,j) + basic_g(ifm)%pi0(k1w,i,j))     &
                              + (1.5 - wtw)                                                &
                              * (basic_g(ifm)%pp(k2w,i,j) + basic_g(ifm)%pi0(k2w,i,j))
            else
               pi0_mean(i,j)  = (wtw + .5)                                                 &
                              * (basic_g(ifm)%pp(k2w,i,j) + basic_g(ifm)%pi0(k2w,i,j))     &
                              + (.5 - wtw)                                                 &
                              * (basic_g(ifm)%pp(k3w,i,j) + basic_g(ifm)%pi0(k3w,i,j))
            end if


            if (iswrtyp == 3) then
               !----- We obtain the diffuse radiation straight from Harrington. -----------!
               rshortd(i,j)  = radiate_g(ifm)%rshort_diffuse(i,j)
               nir_beam(i,j) = fnir_beam_def * (radiate_g(ifm)%rshort(i,j)-rshortd(i,j))
               nir_diff(i,j) = fnir_diff_def * rshortd(i,j)
               par_beam(i,j) = fvis_beam_def * (radiate_g(ifm)%rshort(i,j)-rshortd(i,j))
               par_diff(i,j) = fvis_diff_def * rshortd(i,j)

            else
               !---------------------------------------------------------------------------!
               !      The following subroutine estimates the diffuse shortwave radiation.  !
               ! This is a gross approximation that uses constant scattering coefficients. !
               !---------------------------------------------------------------------------!
               select case (imetrad)
               case (0,1)
                  call short2diff_sib(radiate_g(ifm)%rshort(i,j),radiate_g(ifm)%cosz(i,j)  &
                                     ,rshortd(i,j))
                  nir_beam(i,j) = fnir_beam_def * (radiate_g(ifm)%rshort(i,j)-rshortd(i,j))
                  nir_diff(i,j) = fnir_diff_def * rshortd(i,j)
                  par_beam(i,j) = fvis_beam_def * (radiate_g(ifm)%rshort(i,j)-rshortd(i,j))
                  par_diff(i,j) = fvis_diff_def * rshortd(i,j)
               case (2)
                  press = exner2press(pi0_mean(i,j))
               
                  call short_bdown_weissnorman(radiate_g(ifm)%rshort_diffuse(i,j),press    &
                                              ,radiate_g(ifm)%cosz(i,j),par_beam(i,j)      &
                                              ,par_diff(i,j),nir_beam(i,j),nir_diff(i,j)   &
                                              ,rshortd(i,j) )
               end select
            end if
        end do
      end do
   end select

   !---------------------------------------------------------------------------------------!
   !     With these averages, we can start copying the values to the ED structures.        !
   !---------------------------------------------------------------------------------------!
   polyloop1st: do ipy=1,cgrid%npolygons
      
      !---- Aliases for grid points of interest. ------------------------------------------!
      ix =  cgrid%ilon(ipy)
      iy =  cgrid%ilat(ipy)
      k2w   = nint(grid_g(ifm)%flpw(ix,iy))
      k1w   = k2w - 1

      !------------------------------------------------------------------------------------!
      !     Save the radiation terms.                                                      !
      !------------------------------------------------------------------------------------!
      cgrid%met(ipy)%rshort         =  radiate_g(ifm)%rshort(ix,iy)
      cgrid%met(ipy)%rshort_diffuse =  rshortd              (ix,iy)
      cgrid%met(ipy)%nir_beam       =  nir_beam             (ix,iy)
      cgrid%met(ipy)%nir_diffuse    =  nir_diff             (ix,iy)
      cgrid%met(ipy)%par_beam       =  par_beam             (ix,iy)
      cgrid%met(ipy)%par_diffuse    =  par_diff             (ix,iy)
      !------------------------------------------------------------------------------------!

      cgrid%met(ipy)%rlong    = radiate_g(ifm)%rlong(ix,iy)
      !----- Converting Exner function to pressure. ---------------------------------------!
      cgrid%met(ipy)%exner    = pi0_mean(ix,iy)
      cgrid%met(ipy)%prss     = exner2press(cgrid%met(ipy)%exner)

      !----- Finding the actual height above ground for 2nd level. ------------------------!
      cgrid%met(ipy)%geoht    = (zt(k2w)-zm(k1w)) * grid_g(ifm)%rtgt(ix,iy)

      !------------------------------------------------------------------------------------!
      !   Finding the kinetic energy (twice its value, to be precise).  It will be con-    !
      ! verted to wind speed later, after calc_met_lapse.                                  !
      !------------------------------------------------------------------------------------!
      cgrid%met(ipy)%vels     = up_mean(ix,iy)**2 + vp_mean(ix,iy)**2

      !------------------------------------------------------------------------------------!
      !    ED needs specific humidity, but BRAMS has mixing ratio, so we must convert      !
      ! before sending to ED.  Temperature is found from the exner function and potential  !
      ! temperature, and CO2 is already in �mol_CO2 / mol_air, no conversion needed...     !
      !------------------------------------------------------------------------------------!
      
      cgrid%met(ipy)%atm_theta    = theta_mean(ix,iy)
      cgrid%met(ipy)%atm_tmp      = extheta2temp( cgrid%met(ipy)%exner                     &
                                                , cgrid%met(ipy)%atm_theta )
      cgrid%met(ipy)%atm_co2      = max(atm_co2_min,co2p_mean(ix,iy) + co2_offset)


      !------------------------------------------------------------------------------------!
      !     Check the relative humidity associated with the current pressure, temperature, !
      ! and mixing ratio.  Impose lower and upper bounds as prescribed by the variables    !
      ! atm_rhv_min and atm_rhv_max (from met_driver_coms.f90, and defined at the          !
      ! init_met_params subroutine in ed_params.f90).                                      !
      !------------------------------------------------------------------------------------!
      relhum = rehuil(cgrid%met(ipy)%prss,cgrid%met(ipy)%atm_tmp,rv_mean(ix,iy),.false.)
      !------------------------------------------------------------------------------------!
      !      Check whether the relative humidity is off-bounds.  If it is, then we re-     !
      ! calculate mixing ratio exactly at the limit, then convert it to specific humidity. !
      ! Also, in case we update rv_mean, we must make sure that rv_mean doesn't become     !
      ! larger than rtp_mean.                                                              !
      !------------------------------------------------------------------------------------!
      if (relhum < atm_rhv_min) then
         relhum          = atm_rhv_min
         rv_mean(ix,iy)  = ptrh2rvapil(relhum,cgrid%met(ipy)%prss,cgrid%met(ipy)%atm_tmp   &
                                      ,.false.)
         rtp_mean(ix,iy) = max(rtp_mean(ix,iy), rv_mean(ix,iy))
      elseif (relhum > atm_rhv_max) then
         relhum          = atm_rhv_max
         rv_mean(ix,iy)  = ptrh2rvapil(relhum,cgrid%met(ipy)%prss,cgrid%met(ipy)%atm_tmp   &
                                      ,.false.)
         rtp_mean(ix,iy) = max(rtp_mean(ix,iy), rv_mean(ix,iy))
      end if
      !----- Find the specific humidity. --------------------------------------------------!
      cgrid%met(ipy)%atm_shv = rtp_mean(ix,iy) / (1. + rtp_mean(ix,iy))
      !------------------------------------------------------------------------------------!

      !----- Find the ice-vapour equivalent potential temperature. ------------------------!
      cgrid%met(ipy)%atm_theiv = thetaeiv(cgrid%met(ipy)%atm_theta,cgrid%met(ipy)%prss     &
                                         ,cgrid%met(ipy)%atm_tmp,rtp_mean(ix,iy)           &
                                         ,rtp_mean(ix,iy))
   end do polyloop1st

   !----- Filling the precipitation arrays. -----------------------------------------------!
   call fill_site_precip(ifm,cgrid,m2,m3,ia,iz,ja,jz,init)

  
   polyloop2nd: do ipy = 1,cgrid%npolygons

      !------------------------------------------------------------------------------------!
      !      If this is the first call, it is only looking for atm_tmp and atm_shv, so we  !
      ! can bypass the error check.                                                        !
      !------------------------------------------------------------------------------------!
      if (init) cgrid%met(ipy)%rlong=rlong_min


      !------ Apply met to sites, and adjust met variables for topography. ----------------!
      call calc_met_lapse(cgrid,ipy)

      !----- Converting vels to wind (m/s) ------------------------------------------------!
      cgrid%met(ipy)%vels = sqrt(max(0.0,cgrid%met(ipy)%vels))


      cpoly => cgrid%polygon(ipy)
      siteloop: do isi = 1,cpoly%nsites
         
         !----- Vels.  At this point vels is 2*Kinetic Energy, take the square root. ------!
         cpoly%met(isi)%vels        = sqrt(max(0.0,cpoly%met(isi)%vels))
         cpoly%met(isi)%vels_stab   = max(0.1,cpoly%met(isi)%vels)
         cpoly%met(isi)%vels_unstab = max(1.0,cpoly%met(isi)%vels_stab)



         !---------------------------------------------------------------------------------!
         !     We now find some derived properties.  In case several sites exist, the      !
         ! lapse rate was applied to pressure, temperature, and mixing ratio.  Then we     !
         ! calculate the Exner function, potential temperature and equivalent potential    !
         ! temperature, so it will respect the ideal gas law and first law of thermo-      !
         ! dynamics.                                                                       !
         !---------------------------------------------------------------------------------!
         cpoly%met(isi)%exner        = press2exner (cpoly%met(isi)%prss)
         cpoly%met(isi)%atm_theta    = extemp2theta( cpoly%met(isi)%exner                  &
                                                   , cpoly%met(isi)%atm_tmp )

         !---------------------------------------------------------------------------------!
         !     Check the relative humidity associated with the current pressure, temper-   !
         ! ature, and specific humidity.  Impose lower and upper bounds as prescribed by   !
         ! the variables atm_rhv_min and atm_rhv_max (from met_driver_coms.f90, and        !
         ! defined at the init_met_params subroutine in ed_params.f90).                    !
         !---------------------------------------------------------------------------------!
         relhum = rehuil(cpoly%met(isi)%prss,cpoly%met(isi)%atm_tmp,cpoly%met(isi)%atm_shv &
                        ,.true.)
         !---------------------------------------------------------------------------------!
         !      Check whether the relative humidity is off-bounds.  If it is, then we re-  !
         ! calculate the mixing ratio and convert to specific humidity.                    !
         !---------------------------------------------------------------------------------!
         if (relhum < atm_rhv_min) then
            relhum = atm_rhv_min
            cpoly%met(isi)%atm_shv = ptrh2rvapil( relhum                                   &
                                                , cpoly%met(isi)%prss                      &
                                                , cpoly%met(isi)%atm_tmp                   &
                                                , .true.)
         elseif (relhum > atm_rhv_max) then
            relhum = atm_rhv_max
            cpoly%met(isi)%atm_shv = ptrh2rvapil( relhum                                   &
                                                , cpoly%met(isi)%prss                      &
                                                , cpoly%met(isi)%atm_tmp                   &
                                                , .true.)
         end if
         !---------------------------------------------------------------------------------!

         !----- Find the atmospheric equivalent potential temperature. --------------------!
         rvaux = cpoly%met(isi)%atm_shv / (1.0 - cpoly%met(isi)%atm_shv)
         cpoly%met(isi)%atm_theiv = thetaeiv(cpoly%met(isi)%atm_theta,cpoly%met(isi)%prss  &
                                            ,cpoly%met(isi)%atm_tmp,rvaux,rvaux)

         !----- Solar radiation -----------------------------------------------------------!
         cpoly%met(isi)%rshort_diffuse = cpoly%met(isi)%par_diffuse                        &
                                       + cpoly%met(isi)%nir_diffuse

         cpoly%met(isi)%rshort         = cpoly%met(isi)%rshort_diffuse                     &
                                       + cpoly%met(isi)%par_beam + cpoly%met(isi)%nir_beam

         !---------------------------------------------------------------------------------!
         !    Finding the mean energy and depth of precipitation rates: qpcpg and dpcpg,   !
         ! respectively.  This is currently using the same parametrisation from the off-   !
         ! line model.  While this is the best we can do for cumulus precipitation, we     !
         ! should be using the actual rates from the microphysics for the microphysics     !
         ! precipitation.                                                                  !
         !    The fractions of ice and snow density are based on:                          !
         ! Jin et al. 1999, Hydrol. Process. 13: 2467-2482, table 2                        !
         !    (modified 11/16/09 by MCD).                                                  !
         !---------------------------------------------------------------------------------!
         if (cpoly%met(isi)%atm_tmp > (t3ple + 2.5)) then
            !----- Rain only. -------------------------------------------------------------!
            fice = 0.0
            cpoly%met(isi)%dpcpg = max(0.0, cpoly%met(isi)%pcpg) *wdnsi

         elseif (cpoly%met(isi)%atm_tmp <= (t3ple + 2.5) .and.                             &
                 cpoly%met(isi)%atm_tmp  > (t3ple + 2.0) ) then
            !------------------------------------------------------------------------------!
            !     60% snow, 40% rain. (N.B. May not be appropriate for sub-tropical        !
            ! regions where the level of the melting layer is higher...).                  !
            !------------------------------------------------------------------------------!
            fice  = 0.6
            snden = 189.0
            cpoly%met(isi)%dpcpg = max(0.0, cpoly%met(isi)%pcpg)                           &
                                 * ((1.0-fice) * wdnsi + fice / snden)

         elseif (cpoly%met(isi)%atm_tmp <= (t3ple + 2.0) .and.                             &
                 cpoly%met(isi)%atm_tmp > t3ple          ) then
            !------------------------------------------------------------------------------!
            !     Increasing the fraction of snow. (N.B. May not be appropriate for        !
            ! sub-tropical regions where the level of the melting layer is higher...).     !
            !------------------------------------------------------------------------------!
            fice  = min(1.0, 1.+(54.62 - 0.2*cpoly%met(isi)%atm_tmp))
            snden = (50.0+1.7*(cpoly%met(isi)%atm_tmp-258.15)**1.5 )
            cpoly%met(isi)%dpcpg = max(0.0, cpoly%met(isi)%pcpg)                           &
                                 * ((1.0-fice) * wdnsi + fice / snden)

         elseif (cpoly%met(isi)%atm_tmp <= t3ple         .and.                             &
                 cpoly%met(isi)%atm_tmp > (t3ple - 15.0) ) then
            !----- Below freezing point, snow only. ---------------------------------------!
            fice  = 1.0
            snden = (50.0+1.7*(cpoly%met(isi)%atm_tmp-258.15)**1.5 )
            cpoly%met(isi)%dpcpg = max(0.0, cpoly%met(isi)%pcpg) / snden

         else ! if (copy%met(isi)%atm_tmp < (t3ple - 15.0)) then
            !----- Below freezing point, snow only. ---------------------------------------!
            fice  = 1.0
            snden = 50.
            cpoly%met(isi)%dpcpg = max(0.0, cpoly%met(isi)%pcpg) / snden

         end if
         !---------------------------------------------------------------------------------!

         !---------------------------------------------------------------------------------!
         !     Set internal energy.  This will be the precipitation times the specific     !
         ! internal energy of water (above or at triple point) multiplied by the liquid    !
         ! fraction plus the specific internal energy of ice (below or at the triple       !
         ! point) multiplied by the ice fraction.                                          !
         !---------------------------------------------------------------------------------!
         cpoly%met(isi)%qpcpg = max(0.0, cpoly%met(isi)%pcpg)                              &
                              * ( (1.0 - fice)                                             &
                                * tl2uint(max(t3ple,cpoly%met(isi)%atm_tmp),1.0)           &
                                + fice * tl2uint(min(cpoly%met(isi)%atm_tmp,t3ple),0.0) )
         !---------------------------------------------------------------------------------!

      end do siteloop
   end do polyloop2nd

   !----- Allocate the 2-D arrays. --------------------------------------------------------!
   deallocate(rshortd    )
   deallocate(par_beam   )
   deallocate(par_diff   )
   deallocate(nir_beam   )
   deallocate(nir_diff   )
   deallocate(up_mean    )
   deallocate(vp_mean    )
   deallocate(pi0_mean   )
   deallocate(rv_mean    )
   deallocate(rtp_mean   )
   deallocate(theta_mean )
   deallocate(co2p_mean  )

   return
end subroutine copy_atm2lsm
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
!      This subroutine will consider both kinds of precipitation (cumulus scheme + bulk    !
! microphysics) to retrieve precipitation for ED. It is currently a simplified method,     !
! because it doesn't fully take advantage of the bulk microphysics details.                !
!------------------------------------------------------------------------------------------!
subroutine fill_site_precip(ifm,cgrid,m2,m3,ia,iz,ja,jz,init)
   use mem_cuparm   , only : cuparm_g     & ! structure
                           , nnqparm      ! ! intent(in)
   use mem_micro    , only : micro_g      ! ! structure
   use micphys      , only : availcat     ! ! intent(in)
   use therm_lib    , only : bulk_on      ! ! intent(in)
   use mem_basic    , only : basic_g      ! ! structure
   use ed_state_vars, only : edtype       ! ! structure
   use mem_edcp     , only : ed_precip_g  ! ! structure
   use ed_misc_coms , only : dtlsm        ! ! intent(in)
   implicit none
   !----- Arguments. ----------------------------------------------------------------------!
   type(edtype)          , target     :: cgrid
   integer               , intent(in) :: ifm,m2,m3,ia,iz,ja,jz
   logical               , intent(in) :: init
   !----- Local variables -----------------------------------------------------------------!
   integer                            :: i,j,n,ix,iy,ipy
   real, dimension(m2,m3)             :: conprr_mean,bulkprr_mean
   real                               :: totpcp, dtlsmi
   logical                            :: cumulus_on
   !---------------------------------------------------------------------------------------!


   !----- Some aliases.  ------------------------------------------------------------------!
   cumulus_on   = nnqparm(ifm) > 0
   dtlsmi = 1./dtlsm


   !----- Zero the precipitation structures. ----------------------------------------------!
   do ipy=1,cgrid%npolygons
      cgrid%met(ipy)%pcpg = 0.
   end do
   conprr_mean (:,:) = 0.
   bulkprr_mean(:,:) = 0.

   !---------------------------------------------------------------------------------------!
   !     Here we need to check which kind of precipitation we have available, since both   !
   ! cumulus and bulk microphysics may or may not exist.                                   !
   !---------------------------------------------------------------------------------------!
   !----- Cumulus clouds from cumulus scheme. ---------------------------------------------!
   if (cumulus_on) then
      !------------------------------------------------------------------------------------!
      !     We need to use difference in aconpr instead of conprr because cumulus parame-  !
      ! trisation is usually called less often than ED.  Therefore, using conprr would     !
      ! repeat the same precipitation rate until cumulus is called again, which would make !
      ! ED overestimate the total convective precipitation.  Using aconpr and comparing to !
      ! the previous one will give the average precipitation rate between two ED calls, so !
      ! it will take the right total amount of convective precipitation.                   !
      !------------------------------------------------------------------------------------!
      do j=ja,jz
         do i=ia,iz
            conprr_mean(i,j) = dtlsmi * ( cuparm_g(ifm)%aconpr(i,j)                        &
                                        - ed_precip_g(ifm)%prev_aconpr(i,j) )
            ed_precip_g(ifm)%prev_aconpr(i,j) = cuparm_g(ifm)%aconpr(i,j)
         end do
      end do
   end if
   !----- Bulk microphysics method. -------------------------------------------------------!
   if (bulk_on) then

      !------------------------------------------------------------------------------------!
      !     Again, we need to use the accumulated precipitation because the bulk micro-    !
      ! physics is called every BRAMS time step.  Therefore, if we use pcpg we will cap-   !
      ! ture the precipitation that happened only at one time step before the current ED   !
      ! call, which would underestimate the resolved precipitation unless                  !
      ! dtlsm = dtlong(ifm).  Using the accumulated precipitation difference will give the !
      ! amount of resolved precipitation since the last ED call, thus taking the right     !
      ! amount of resolved precipitation.                                                  !
      !------------------------------------------------------------------------------------!
      do j=ja,jz
         do i=ia,iz
            !------------------------------------------------------------------------------!
            !     Here I add all forms of precipitation available, previously converted    !
            ! into the equivalent amount of liquid water.  Even when the bulk microphysics !
            ! scheme is on, we may not have all forms of precipitation, so we check one by !
            ! one before adding them.                                                      !
            !------------------------------------------------------------------------------!
            totpcp = 0.
            if (availcat(2)) totpcp = totpcp + micro_g(ifm)%accpr(i,j) ! Rain
            if (availcat(3)) totpcp = totpcp + micro_g(ifm)%accpp(i,j) ! Pristine ice
            if (availcat(4)) totpcp = totpcp + micro_g(ifm)%accps(i,j) ! Snow
            if (availcat(5)) totpcp = totpcp + micro_g(ifm)%accpa(i,j) ! Aggregates
            if (availcat(6)) totpcp = totpcp + micro_g(ifm)%accpg(i,j) ! Graupel
            if (availcat(7)) totpcp = totpcp + micro_g(ifm)%accph(i,j) ! Hail
            !----- Finding the average rate. ----------------------------------------------!
            bulkprr_mean(i,j) = (totpcp-ed_precip_g(ifm)%prev_abulkpr(i,j)) * dtlsmi
            !----- Save current amount for next call. -------------------------------------!
            ed_precip_g(ifm)%prev_abulkpr(i,j) = totpcp
         end do
      end do
   end if

   !----- Now we combine both kinds of precipitation. -------------------------------------!
   if (.not. init) then
      do ipy=1,cgrid%npolygons
         ix =  cgrid%ilon(ipy)
         iy =  cgrid%ilat(ipy)
         cgrid%met(ipy)%pcpg = conprr_mean(ix,iy) + bulkprr_mean(ix,iy)
      end do
   end if
   return
end subroutine fill_site_precip
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
!      Subroutine to copy the old "future" flux field to the "past".                       !
!------------------------------------------------------------------------------------------!
subroutine copy_fluxes_future_2_past(ifm)
   use mem_edcp,only: ed_fluxf_g  & ! structure
                    , ed_fluxp_g  ! ! structure
                           
   implicit none
   !----- Arguments. ----------------------------------------------------------------------!
   integer               , intent(in) :: ifm
   !---------------------------------------------------------------------------------------!

   !----- Simple copy of fluxes over land. ------------------------------------------------!
   ed_fluxp_g(ifm)%ustar      = ed_fluxf_g(ifm)%ustar
   ed_fluxp_g(ifm)%tstar      = ed_fluxf_g(ifm)%tstar
   ed_fluxp_g(ifm)%rstar      = ed_fluxf_g(ifm)%rstar
   ed_fluxp_g(ifm)%cstar      = ed_fluxf_g(ifm)%cstar
   ed_fluxp_g(ifm)%zeta       = ed_fluxf_g(ifm)%zeta
   ed_fluxp_g(ifm)%ribulk     = ed_fluxf_g(ifm)%ribulk
   ed_fluxp_g(ifm)%rshort_gnd = ed_fluxf_g(ifm)%rshort_gnd
   ed_fluxp_g(ifm)%rlong_gnd  = ed_fluxf_g(ifm)%rlong_gnd
   ed_fluxp_g(ifm)%albedt     = ed_fluxf_g(ifm)%albedt
   ed_fluxp_g(ifm)%rlongup    = ed_fluxf_g(ifm)%rlongup
   ed_fluxp_g(ifm)%sflux_u    = ed_fluxf_g(ifm)%sflux_u
   ed_fluxp_g(ifm)%sflux_v    = ed_fluxf_g(ifm)%sflux_v
   ed_fluxp_g(ifm)%sflux_w    = ed_fluxf_g(ifm)%sflux_w
   ed_fluxp_g(ifm)%sflux_t    = ed_fluxf_g(ifm)%sflux_t
   ed_fluxp_g(ifm)%sflux_r    = ed_fluxf_g(ifm)%sflux_r
   ed_fluxp_g(ifm)%sflux_c    = ed_fluxf_g(ifm)%sflux_c
   ed_fluxp_g(ifm)%rk4step    = ed_fluxf_g(ifm)%rk4step

   return
end subroutine copy_fluxes_future_2_past
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
!     This subroutine will copy the ED-2 variables that are used by BRAMS in other sub-    !
! routines, such as radiation, turbulence, etc.                                            !
!------------------------------------------------------------------------------------------! 
subroutine copy_fluxes_lsm2atm(ifm)
   use ed_state_vars , only : edgrid_g    & ! structure
                            , edtype      & ! structure
                            , polygontype & ! structure
                            , sitetype    ! ! structure
   use mem_edcp      , only : ed_fluxf_g  & ! structure
                            , ed_flux     ! ! structure
   use soil_coms     , only : nzs         ! ! intent(in)
   use mem_grid      , only : zt          & ! intent(in)
                            , grid_g      & ! structure
                            , dzt         & ! intent(in)
                            , zm          & ! intent(in)
                            , if_adap     & ! intent(in)
                            , jdim        & ! intent(in)
                            , npatch      ! ! intent(in)
   use mem_basic     , only : basic_g     ! ! structure
   use mem_leaf      , only : leaf_g      ! ! structure
   use rconstants    , only : mmcod       ! ! intent(in)
   implicit none
   !----- Arguments. ----------------------------------------------------------------------!
   integer               , intent(in) :: ifm
   !----- Local variables -----------------------------------------------------------------!
   type(edtype)          , pointer    :: cgrid
   type(polygontype)     , pointer    :: cpoly
   type(sitetype)        , pointer    :: csite
   type(ed_flux)         , pointer    :: fluxp
   integer                            :: ipy
   integer                            :: isi
   integer                            :: ix
   integer                            :: iy
   integer                            :: ilp
   integer                            :: k
   integer                            :: k2u
   integer                            :: k3u
   integer                            :: k2u_1
   integer                            :: k3u_1
   integer                            :: k2v
   integer                            :: k3v
   integer                            :: k2v_1
   integer                            :: k3v_1
   real                               :: wtu1
   real                               :: wtu2
   real                               :: wtv1
   real                               :: wtv2
   real                               :: up_mean
   real                               :: vp_mean
   real                               :: cosine
   real                               :: sine
   real                               :: site_area_i
   real(kind=8)                       :: angle
   !---------------------------------------------------------------------------------------!


   !----- Set the pointers, the state variable and the future flux grid. ------------------!
   cgrid => edgrid_g(ifm)
   fluxp => ed_fluxf_g(ifm)
  
   do ipy=1,cgrid%npolygons
      cpoly => cgrid%polygon(ipy)

      ix = cgrid%ilon(ipy)
      iy = cgrid%ilat(ipy)

      !------------------------------------------------------------------------------------!
      !     Find the wind average.  To do this, we first check which vertical coordinate   !
      ! we are using.                                                                      !
      !------------------------------------------------------------------------------------!
      select case(if_adap)
      case (0) !----- Terrain-following coordinate. ---------------------------------------!
         up_mean = (basic_g(ifm)%up(2,ix,iy) + basic_g(ifm)%up(2,ix-1,iy)) * 0.5
         vp_mean = (basic_g(ifm)%vp(2,ix,iy) + basic_g(ifm)% vp(2,ix,iy-jdim)) * 0.5
      case (1) !----- Adaptive coordinate. ------------------------------------------------!
         !---------------------------------------------------------------------------------!
         !    Find the lowest boundary levels, depending on which kind of variable we are  !
         ! averaging (staggered grid).                                                     !
         !---------------------------------------------------------------------------------!
         !----- U points, need to average between i-1 and i... ----------------------------!
         k2u   = nint(grid_g(ifm)%flpu(ix,iy))
         k3u   = k2u + 1
         k2u_1 = nint(grid_g(ifm)%flpu(ix-1,iy))
         k3u_1 = k2u_1 + 1
         !----- V points, need to average between j-jdim and j... -------------------------!
         k2v   = nint(grid_g(ifm)%flpv(ix,iy))
         k3v   = k2v+1
         k2v_1 = nint(grid_g(ifm)%flpv(ix,iy-jdim))
         k3v_1 = k2v_1 + 1
         !---------------------------------------------------------------------------------!
         !     Compute the weights for lowest predicted points, relative to points above   !
         ! them.                                                                           !
         !---------------------------------------------------------------------------------!
         wtu1 = grid_g(ifm)%aru(k2u_1,ix-1,iy)    / grid_g(ifm)%aru(k3u_1,ix-1,iy)
         wtu2 = grid_g(ifm)%aru(k2u,ix,iy)        / grid_g(ifm)%aru(k3u,ix,iy)
         wtv1 = grid_g(ifm)%arv(k2v_1,ix,iy-jdim) / grid_g(ifm)%arv(k3v_1,ix,iy-jdim)
         wtv2 = grid_g(ifm)%arv(k2v,ix,iy)        / grid_g(ifm)%arv(k3v,ix,iy)
         up_mean = (        wtu1  * basic_g(ifm)%up(k2u_1,ix-1,iy)                         &
                   +  (1. - wtu1) * basic_g(ifm)%up(k3u_1,ix-1,iy)                         &
                   +        wtu2  * basic_g(ifm)%up(k2u,ix,iy)                             &
                   +  (1. - wtu2) * basic_g(ifm)%up(k3u,ix,iy)       ) * .5
         vp_mean = (        wtv1  * basic_g(ifm)%vp(k2v_1,ix,iy-jdim)                      &
                   +  (1. - wtv1) * basic_g(ifm)%vp(k3v_1,ix,iy-jdim)                      &
                   +        wtv2  * basic_g(ifm)%vp(k2v,ix,iy)                             &
                   +  (1. - wtv2) * basic_g(ifm)%vp(k3v,ix,iy)       ) * .5
      end select
      !----- This is safer than using u/sqrt(u�+v�), when u and v are both zero... --------!
      angle  = datan2(dble(vp_mean),dble(up_mean))
      cosine = sngl(dcos(angle))
      sine   = sngl(dsin(angle))


      !------------------------------------------------------------------------------------!
      !    Find the averaged flux variables.  For most variables, it will be simply the    !
      ! site and patch weighted average, in which the weights are the site and patch       !
      ! areas.  The exceptions are commented.                                              !
      !------------------------------------------------------------------------------------!
      do isi=1,cpoly%nsites
         csite => cpoly%site(isi)
         
         !---- Leaf "patch" is offset by 1 because the first patch is water. --------------!
         ilp = isi + 1

         !---- Inverse of the sum of the patch area, used to normalise site averages. -----!
         site_area_i = 1./sum(csite%area)

         fluxp%ustar(ix,iy,ilp) = sum(csite%area * csite%ustar) * site_area_i
         fluxp%tstar(ix,iy,ilp) = sum(csite%area * csite%tstar) * site_area_i
         fluxp%cstar(ix,iy,ilp) = sum(csite%area * csite%cstar) * site_area_i

         !---------------------------------------------------------------------------------!
         !     BRAMS needs rstar (mixing ratio), but ED computes qstar (specific humidity) !
         ! characteristic friction scales.  We must find the appropriate conversion.       !
         !---------------------------------------------------------------------------------!
         fluxp%rstar(ix,iy,ilp) = site_area_i                                              &
                                * sum(csite%area * csite%qstar / (1.-csite%can_shv))       &
                                / (1. - cpoly%met(isi)%atm_shv)
         !---------------------------------------------------------------------------------!

         !---------------------------------------------------------------------------------!
         !     Linear interpolation is not the best method here but the following vari-    !
         ! ables are diagnostic only.                                                      !
         !---------------------------------------------------------------------------------!
         fluxp%zeta  (ix,iy,ilp) = sum(csite%area * csite%zeta  ) * site_area_i
         fluxp%ribulk(ix,iy,ilp) = sum(csite%area * csite%ribulk) * site_area_i

         !---------------------------------------------------------------------------------!
         !     The flux of momentum for the horizontal wind needs to be split with the     !
         ! appropriate direction.                                                          !
         !---------------------------------------------------------------------------------!
         fluxp%sflux_u(ix,iy,ilp) = cosine * sum(csite%area * csite%upwp) * site_area_i
         fluxp%sflux_v(ix,iy,ilp) =   sine * sum(csite%area * csite%upwp) * site_area_i
         fluxp%sflux_w(ix,iy,ilp) =          sum(csite%area * csite%wpwp) * site_area_i
         fluxp%sflux_t(ix,iy,ilp) =          sum(csite%area * csite%tpwp) * site_area_i
         fluxp%sflux_c(ix,iy,ilp) =          sum(csite%area * csite%cpwp) * site_area_i
         !---------------------------------------------------------------------------------!


         !---------------------------------------------------------------------------------!
         !     Same thing as in the rstar case: we must convert the ED-2 flux (specific    !
         ! volume) to mixing ratio, which is what BRAMS expects.                           !
         !---------------------------------------------------------------------------------!
         fluxp%sflux_r(ix,iy,ilp) = site_area_i                                            &
                                  * sum(csite%area * csite%qpwp / (1.-csite%can_shv))      &
                                  / (1. - cpoly%met(isi)%atm_shv)
         !---------------------------------------------------------------------------------!


         !---------------------------------------------------------------------------------!
         !   Include emission and reflected longwave in rlongup.                           !
         !---------------------------------------------------------------------------------!
         fluxp%rlongup(ix,iy,ilp) = sum( csite%area  * ( csite%rlongup                     &
                                                       + cpoly%met(isi)%rlong              &
                                                       * csite%rlong_albedo  ) )           &
                                  * site_area_i
         !---------------------------------------------------------------------------------!


         !---------------------------------------------------------------------------------!
         !    Total albedo is the average between albedo for direct (beam) and diffuse.    !
         !---------------------------------------------------------------------------------!
         fluxp%albedt(ix,iy,ilp)  = sum(csite%area * csite%albedo) * site_area_i
         !---------------------------------------------------------------------------------!


         !---------------------------------------------------------------------------------!
         !    Total albedo is the average between albedo for direct (beam) and diffuse.    !
         !---------------------------------------------------------------------------------!
         fluxp%rshort_gnd    (ix,iy,ilp) = sum(csite%area * csite%rshort_g) * site_area_i
         do k=1,nzs
            fluxp%rshort_gnd (ix,iy,ilp) = fluxp%rshort_gnd(ix,iy,ilp)                     &
                                         + sum(csite%area * csite%rshort_s(k,:))           &
                                         * site_area_i
         end do
         fluxp%rlong_gnd     (ix,iy,ilp) = sum(csite%area * ( csite%rlong_g                &
                                                            + csite%rlong_s ))             &
                                         * site_area_i
         !---------------------------------------------------------------------------------!
      end do
   end do

   return
end subroutine copy_fluxes_lsm2atm
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
!    This subroutine will assign initial values for some of the state and flux variables   !
! in LEAF-3, which will get the data from ED-2.  Also, it will perform initialisation of   !
! some structures that are used in the ED-2/LEAF-3 interfacing.                            !
!------------------------------------------------------------------------------------------!
subroutine initialize_ed2leaf(ifm)
  
   use mem_edcp     , only : ed_fluxf_g     & ! structure
                           , ed_fluxp_g     & ! structure
                           , ed_precip_g    ! ! structure
   use node_mod     , only : mxp            & ! intent(in)
                           , myp            & ! intent(in)
                           , ia             & ! intent(in)
                           , iz             & ! intent(in)
                           , ja             & ! intent(in)
                           , jz             & ! intent(in)
                           , mynum          ! ! intent(in)
   use mem_leaf     , only : leaf_g         ! ! structure
   use mem_basic    , only : basic_g        ! ! structure
   use mem_grid     , only : grid_g         & ! structure
                           , zt             & ! intent(in)
                           , dzt            & ! intent(in)
                           , zm             & ! intent(in)
                           , if_adap        & ! intent(in)
                           , jdim           & ! intent(in)
                           , npatch         ! ! intent(in)
   use leaf_coms    , only : can_depth      ! ! intent(in)
   use mem_cuparm   , only : cuparm_g       & ! structure
                           , nnqparm        ! ! intent(in)
   use micphys      , only : availcat       ! ! intent(in)
   use mem_micro    , only : micro_g        ! ! structure
   use therm_lib    , only : bulk_on        & ! intent(in)
                           , reducedpress   & ! function
                           , thetaeiv       & ! function
                           , exner2press    & ! function
                           , extheta2temp   ! ! function
   use ed_state_vars, only : edgrid_g       & ! intent(in)
                           , edtype         ! ! structure
   implicit none
   !----- Arguments. ----------------------------------------------------------------------!
   integer             , intent(in)  :: ifm
   !----- Local variables -----------------------------------------------------------------!
   type(edtype)        , pointer     :: cgrid
   integer                           :: i
   integer                           :: j
   integer                           :: k2w
   integer                           :: k3w
   integer                           :: k1w
   integer                           :: ilp
   real                              :: topma_t
   real                              :: wtw
   real                              :: atm_prss
   real                              :: atm_shv
   real                              :: atm_temp
   real, dimension(:,:), allocatable :: theta_mean
   real, dimension(:,:), allocatable :: thil_mean
   real, dimension(:,:), allocatable :: pi0_mean
   real, dimension(:,:), allocatable :: rv_mean
   real, dimension(:,:), allocatable :: rtp_mean
   real, dimension(:,:), allocatable :: geoht
   real                              :: totpcp
   logical                           :: cumulus_on
   !---------------------------------------------------------------------------------------!

   !----- Some aliases.  ------------------------------------------------------------------!
   cumulus_on   =  nnqparm(ifm) > 0
   cgrid        => edgrid_g(ifm)

   !----- Allocate temporary variables. ---------------------------------------------------!
   allocate (theta_mean (mxp,myp))
   allocate (thil_mean  (mxp,myp))
   allocate (pi0_mean   (mxp,myp))
   allocate (rv_mean    (mxp,myp))
   allocate (rtp_mean   (mxp,myp))
   allocate (geoht      (mxp,myp))
   !---------------------------------------------------------------------------------------!



   !---------------------------------------------------------------------------------------!
   !    Computing the bottom=most layer, then transfer the value to state variables.  The  !
   ! bottom-most layer definition depends on the vertical coordinate.                      !
   !---------------------------------------------------------------------------------------!
   select case (if_adap)
   case (0) !------ Terrain-following coordinates. ----------------------------------------!
      do j=1,myp
         do i=1,mxp
            theta_mean(i,j) = basic_g(ifm)%theta(2,i,j)
            thil_mean(i,j)  = basic_g(ifm)%thp(2,i,j)
            rv_mean(i,j)    = basic_g(ifm)%rv(2,i,j)
            rtp_mean(i,j)   = basic_g(ifm)%rtp(2,i,j)
            pi0_mean(i,j)   = ( basic_g(ifm)%pp(1,i,j)  + basic_g(ifm)%pp(2,i,j)           &
                              + basic_g(ifm)%pi0(1,i,j) + basic_g(ifm)%pi0(2,i,j) ) * 0.5
            geoht(i,j)      = (zt(2)-zm(1)) * grid_g(ifm)%rtgt(i,j)
         end do
      end do
   case (1)
      do j=1,myp
         do i=1,mxp
            !----- Weighted average -------------------------------------------------------!
            k2w = nint(grid_g(ifm)%flpw(i,j)) 
            k1w = k2w - 1
            k3w = k2w + 1
            topma_t = .25 * ( grid_g(ifm)%topma(i,j) + grid_g(ifm)%topma(i-1,j)            &
                            + grid_g(ifm)%topma(i,j-jdim) + grid_g(ifm)%topma(i-1,j-jdim))
            wtw     = (zm(k2w) - topma_t) * dzt(k2w)

            theta_mean(i,j) =       wtw  * basic_g(ifm)%theta(k2w,i,j)                     &
                            + (1. - wtw) * basic_g(ifm)%theta(k3w,i,j)
            thil_mean(i,j)  =       wtw  * basic_g(ifm)%thp(k2w,i,j)                       &
                            + (1. - wtw) * basic_g(ifm)%thp(k3w,i,j)
            rv_mean(i,j)    =       wtw  * basic_g(ifm)%rv(k2w,i,j)                        &
                            + (1. - wtw) * basic_g(ifm)%rv(k3w,i,j)
            rtp_mean(i,j)   =       wtw  * basic_g(ifm)%rtp(k2w,i,j)                       &
                            + (1. - wtw) * basic_g(ifm)%rtp(k3w,i,j)

            if (wtw >= .5) then
               pi0_mean(i,j)  = (wtw - .5)                                                 &
                              * (basic_g(ifm)%pp(k1w,i,j) + basic_g(ifm)%pi0(k1w,i,j))     &
                              + (1.5 - wtw)                                                &
                              * (basic_g(ifm)%pp(k2w,i,j) + basic_g(ifm)%pi0(k2w,i,j))
            else
               pi0_mean(i,j)  = (wtw + .5)                                                 &
                              * (basic_g(ifm)%pp(k2w,i,j) + basic_g(ifm)%pi0(k2w,i,j))     &
                              + (.5 - wtw)                                                 &
                              * (basic_g(ifm)%pp(k3w,i,j) + basic_g(ifm)%pi0(k3w,i,j))
            end if

            geoht(i,j)        = (zt(k2w)-zm(k1w)) * grid_g(ifm)%rtgt(i,j)
         end do
      end do
   end select

   do j=1,myp
      do i=1,mxp
         !----- Find the atmospheric pressure and specific humidity. ----------------------!
         atm_prss                     = exner2press(pi0_mean(i,j))
         atm_shv                      = rtp_mean(i,j) / (1. + rtp_mean(i,j))
         atm_temp                     = extheta2temp(pi0_mean(i,j),theta_mean(i,j))

         !----- Compute the state variables. ----------------------------------------------!
         leaf_g(ifm)%can_theta(i,j,1) =  theta_mean(i,j)
         leaf_g(ifm)%can_rvap (i,j,1) =  rv_mean(i,j)
         leaf_g(ifm)%can_prss (i,j,1) =  reducedpress(atm_prss,theta_mean(i,j),atm_shv     &
                                                     ,geoht(i,j),theta_mean(i,j)           &
                                                     ,atm_shv,can_depth)
         leaf_g(ifm)%can_theiv(i,j,1) =  thetaeiv(thil_mean(i,j),atm_prss,atm_temp         &
                                                 ,rtp_mean(i,j),rtp_mean(i,j))
         leaf_g(ifm)%gpp         (i,j,1) = 0.0
         leaf_g(ifm)%resphet     (i,j,1) = 0.0
         leaf_g(ifm)%plresp      (i,j,1) = 0.0
         leaf_g(ifm)%sensible_gc (i,j,1) = 0.0
         leaf_g(ifm)%sensible_vc (i,j,1) = 0.0
         leaf_g(ifm)%evap_gc     (i,j,1) = 0.0
         leaf_g(ifm)%evap_vc     (i,j,1) = 0.0
         leaf_g(ifm)%transp      (i,j,1) = 0.0

         do ilp=2,npatch
            leaf_g(ifm)%can_theta   (i,j,ilp) = leaf_g(ifm)%can_theta(i,j,1)
            leaf_g(ifm)%can_theiv   (i,j,ilp) = leaf_g(ifm)%can_theiv(i,j,1)
            leaf_g(ifm)%can_rvap    (i,j,ilp) = leaf_g(ifm)%can_rvap (i,j,1)
            leaf_g(ifm)%can_prss    (i,j,ilp) = leaf_g(ifm)%can_prss(i,j,1)
            leaf_g(ifm)%gpp         (i,j,ilp) = 0.0
            leaf_g(ifm)%resphet     (i,j,ilp) = 0.0
            leaf_g(ifm)%plresp      (i,j,ilp) = 0.0
            leaf_g(ifm)%sensible_gc (i,j,ilp) = 0.0
            leaf_g(ifm)%sensible_vc (i,j,ilp) = 0.0
            leaf_g(ifm)%evap_gc     (i,j,ilp) = 0.0
            leaf_g(ifm)%evap_vc     (i,j,ilp) = 0.0
            leaf_g(ifm)%transp      (i,j,ilp) = 0.0
         end do
      end do
   end do

   !----- De-allocate temporary variables. ------------------------------------------------!
   deallocate (theta_mean)
   deallocate (thil_mean )
   deallocate (pi0_mean  )
   deallocate (rv_mean   )
   deallocate (rtp_mean  )
   deallocate (geoht     )
   !---------------------------------------------------------------------------------------!

   return
end subroutine initialize_ed2leaf
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
!     This subroutine will transfer the fluxes computed in ED-2 to the LEAF-3 arrays, so   !
! the other parts of the code will have the appropriate values.                            !
!------------------------------------------------------------------------------------------!
subroutine transfer_ed2leaf(ifm,timel)
   use mem_edcp      , only : ed_fluxf_g  & ! structure
                            , ed_fluxp_g  & ! structure
                            , edtime1     & ! intent(in)
                            , edtime2     ! ! intent(in)
   use mem_turb      , only : turb_g      ! ! structure
   use rconstants    , only : stefan      & ! intent(in)
                            , grav        ! ! intent(in)
   use mem_leaf      , only : leaf_g      & ! structure
                            , zrough      ! ! intent(in)
   use mem_radiate   , only : radiate_g   ! ! structure
   use node_mod      , only : master_num  & ! intent(in)
                            , mmzp        & ! intent(in)
                            , mmxp        & ! intent(in)
                            , mmyp        & ! intent(in)
                            , ia          & ! intent(in)
                            , iz          & ! intent(in)
                            , ja          & ! intent(in)
                            , jz          & ! intent(in)
                            , ia_1        & ! intent(in)
                            , iz1         & ! intent(in)
                            , ja_1        & ! intent(in)
                            , jz1         & ! intent(in)
                            , ibcon       ! ! intent(in)
   use mem_grid      , only : jdim        & ! intent(in)
                            , npatch      & ! intent(in)
                            , grid_g      ! ! structure
   use ed_state_vars , only : edgrid_g    & ! structure
                            , edtype      & ! structure
                            , polygontype & ! structure
                            , sitetype    ! ! structure
   use soil_coms     , only : soil_rough  ! ! intent(in)
   implicit none
   !----- Arguments. ----------------------------------------------------------------------!
   integer     , intent(in):: ifm
   real(kind=8), intent(in) :: timel
   !----- Local variables -----------------------------------------------------------------!
   type(edtype)     , pointer   :: cgrid
   type(polygontype), pointer   :: cpoly
   type(sitetype)   , pointer   :: csite
   real                         :: tfact
   real                         :: la
   integer                      :: ic
   integer                      :: jc
   integer                      :: ici
   integer                      :: jci
   integer                      :: i
   integer                      :: j
   integer                      :: ix
   integer                      :: iy
   integer                      :: m2
   integer                      :: m3
   integer                      :: ipy
   integer                      :: isi
   integer                      :: ilp
   real                         :: site_area_i
   !---------------------------------------------------------------------------------------!

   !----- Assigning some aliases ----------------------------------------------------------!
   m2 = mmxp(ifm)
   m3 = mmyp(ifm)
   tfact = (timel-edtime1)/(edtime2-edtime1)

  
   !---------------------------------------------------------------------------------------!
   !     Interpolate the fluxes of every leaf patch (ED site) in time, and copy to the     !
   ! leaf structures as they can be used by other parts of BRAMS.                          !
   !---------------------------------------------------------------------------------------!
   do j=ja,jz
      do i=ia,iz
         !----- Reset the radiation data, which will be averaged amongst all sites. -------!
         radiate_g(ifm)%albedt (i,j) = 0.0
         radiate_g(ifm)%rlongup(i,j) = 0.0

         !----- Reset the turbulent flux data, which will be averaged amongst all sites. --!
         turb_g(ifm)%sflux_u   (i,j) = 0.0
         turb_g(ifm)%sflux_v   (i,j) = 0.0
         turb_g(ifm)%sflux_w   (i,j) = 0.0
         turb_g(ifm)%sflux_t   (i,j) = 0.0
         turb_g(ifm)%sflux_r   (i,j) = 0.0
         turb_g(ifm)%sflux_c   (i,j) = 0.0

         do ilp=1,npatch
            !------------------------------------------------------------------------------!
            !      For the stars, we use a simple linear interpolation on time.            !
            !------------------------------------------------------------------------------!
            leaf_g(ifm)%ustar(i,j,ilp) = (1. - tfact) * ed_fluxp_g(ifm)%ustar(i,j,ilp)     &
                                       +       tfact  * ed_fluxf_g(ifm)%ustar(i,j,ilp)
            leaf_g(ifm)%tstar(i,j,ilp) = (1. - tfact) * ed_fluxp_g(ifm)%tstar(i,j,ilp)     &
                                       +       tfact  * ed_fluxf_g(ifm)%tstar(i,j,ilp)
            leaf_g(ifm)%rstar(i,j,ilp) = (1. - tfact) * ed_fluxp_g(ifm)%rstar(i,j,ilp)     &
                                       +       tfact  * ed_fluxf_g(ifm)%rstar(i,j,ilp)
            leaf_g(ifm)%cstar(i,j,ilp) = (1. - tfact) * ed_fluxp_g(ifm)%cstar(i,j,ilp)     &
                                       +       tfact  * ed_fluxf_g(ifm)%cstar(i,j,ilp)

            !------------------------------------------------------------------------------!
            !      The following variables are for diagnostics only, linear interpolation  !
            ! is fine.                                                                     !
            !------------------------------------------------------------------------------!
            leaf_g(ifm)%zeta  (i,j,ilp) = (1. - tfact) * ed_fluxp_g(ifm)%zeta(i,j,ilp)     &
                                        +       tfact  * ed_fluxf_g(ifm)%zeta(i,j,ilp)

            leaf_g(ifm)%ribulk(i,j,ilp) = (1. - tfact) * ed_fluxp_g(ifm)%ribulk(i,j,ilp)   &
                                        +       tfact  * ed_fluxf_g(ifm)%ribulk(i,j,ilp)

            !------------------------------------------------------------------------------!
            !      For the albedo and surface fluxes, we must blend land and water.  The   !
            ! land (ED polygon) is done similarly to the stars, while the water uses the   !
            ! instantaneous value.                                                         !
            !------------------------------------------------------------------------------!
            radiate_g(ifm)%albedt (i,j) = radiate_g(ifm)%albedt(i,j)                       &
                                        + leaf_g(ifm)%patch_area(i,j,ilp)                  &
                                        * ( (1.-tfact) * ed_fluxp_g(ifm)%albedt (i,j,ilp)  &
                                          +     tfact  * ed_fluxf_g(ifm)%albedt (i,j,ilp) )

            radiate_g(ifm)%rlongup(i,j) = radiate_g(ifm)%rlongup(i,j)                      &
                                        + leaf_g(ifm)%patch_area(i,j,ilp)                  &
                                        * ( (1.-tfact) * ed_fluxp_g(ifm)%rlongup(i,j,ilp)  &
                                          +     tfact  * ed_fluxf_g(ifm)%rlongup(i,j,ilp) )

            turb_g(ifm)%sflux_u(i,j)    = turb_g(ifm)%sflux_u(i,j)                         &
                                        + leaf_g(ifm)%patch_area(i,j,ilp)                  &
                                        * ( (1.-tfact) * ed_fluxp_g(ifm)%sflux_u(i,j,ilp)  &
                                          +     tfact  * ed_fluxf_g(ifm)%sflux_u(i,j,ilp))

            turb_g(ifm)%sflux_v(i,j)    = turb_g(ifm)%sflux_v(i,j)                         &
                                        + leaf_g(ifm)%patch_area(i,j,ilp)                  &
                                        * ( (1.-tfact) * ed_fluxp_g(ifm)%sflux_v(i,j,ilp)  &
                                          +     tfact  * ed_fluxf_g(ifm)%sflux_v(i,j,ilp))

            turb_g(ifm)%sflux_w(i,j)    = turb_g(ifm)%sflux_w(i,j)                         &
                                        + leaf_g(ifm)%patch_area(i,j,ilp)                  &
                                        * ( (1.-tfact) * ed_fluxp_g(ifm)%sflux_w(i,j,ilp)  &
                                          +     tfact  * ed_fluxf_g(ifm)%sflux_w(i,j,ilp))

            turb_g(ifm)%sflux_t(i,j)    = turb_g(ifm)%sflux_t(i,j)                         &
                                        + leaf_g(ifm)%patch_area(i,j,ilp)                  &
                                        * ( (1.-tfact) * ed_fluxp_g(ifm)%sflux_t(i,j,ilp)  &
                                          +     tfact  * ed_fluxf_g(ifm)%sflux_t(i,j,ilp))

            turb_g(ifm)%sflux_r(i,j)    = turb_g(ifm)%sflux_r(i,j)                         &
                                        + leaf_g(ifm)%patch_area(i,j,ilp)                  &
                                        * ( (1.-tfact) * ed_fluxp_g(ifm)%sflux_r(i,j,ilp)  &
                                          +     tfact  * ed_fluxf_g(ifm)%sflux_r(i,j,ilp))

            turb_g(ifm)%sflux_c(i,j)    = turb_g(ifm)%sflux_c(i,j)                         &
                                        + leaf_g(ifm)%patch_area(i,j,ilp)                  &
                                        * ( (1.-tfact) * ed_fluxp_g(ifm)%sflux_c(i,j,ilp)  &
                                          +     tfact  * ed_fluxf_g(ifm)%sflux_c(i,j,ilp))
                                          
         end do
      end do
   end do
   !---------------------------------------------------------------------------------------!
   !     Computing the vegetation and patch roughness for land.  We assign the polygon     !
   ! average in both cases.                                                                !
   !---------------------------------------------------------------------------------------!
   cgrid => edgrid_g(ifm)
   polyloop: do ipy=1,cgrid%npolygons
      cpoly => cgrid%polygon(ipy)
      ix     = cgrid%ilon(ipy)
      iy    = cgrid%ilat(ipy)     

      siteloop: do isi = 1, cpoly%nsites
         !------ Leaf patch is offset by 1 because the 1st patch is water. ----------------!
         ilp = isi + 1

         csite => cpoly%site(isi)
         site_area_i = 1. / sum(csite%area(:))

         leaf_g(ifm)%veg_rough   (ix,iy,ilp) = sum(csite%veg_rough(:)*csite%area(:))       &
                                             * site_area_i
         leaf_g(ifm)%patch_rough (ix,iy,ilp) = sum(csite%rough(:)*csite%area(:))           &
                                             * site_area_i
         !----- Not sure about this one, but this is consistent with LEAF-3 ---------------!
         leaf_g(ifm)%patch_rough (ix,iy,ilp) = max(leaf_g(ifm)%patch_rough(ix,iy,ilp)      &
                                                  ,leaf_g(ifm)%soil_rough (ix,iy,ilp)      &
                                                  ,grid_g(ifm)%topzo      (ix,iy)    )
      end do siteloop
   end do polyloop
   !---------------------------------------------------------------------------------------!


   !---------------------------------------------------------------------------------------!
   !    The boundary cells of these arrays have not been filled.  These must be filled by  !
   ! the adjacen cells, likely the 2nd or 2nd to last cell in each row or column.  This    !
   ! will be done only for the true boundary cells (i.e. the ones at the edge of the total !
   ! domain).                                                                              !
   !---------------------------------------------------------------------------------------!



   !----- Western Boundary ----------------------------------------------------------------!
   if (iand(ibcon,1) /= 0) then
      do j=ja,jz
         radiate_g(ifm)%albedt(1,j) = radiate_g(ifm)%albedt(2,j)
         radiate_g(ifm)%rlongup(1,j)= radiate_g(ifm)%rlongup(2,j)

         turb_g(ifm)%sflux_u(1,j)   = turb_g(ifm)%sflux_u(2,j)
         turb_g(ifm)%sflux_v(1,j)   = turb_g(ifm)%sflux_v(2,j)
         turb_g(ifm)%sflux_w(1,j)   = turb_g(ifm)%sflux_w(2,j)
         turb_g(ifm)%sflux_t(1,j)   = turb_g(ifm)%sflux_t(2,j)
         turb_g(ifm)%sflux_r(1,j)   = turb_g(ifm)%sflux_r(2,j)
         turb_g(ifm)%sflux_c(1,j)   = turb_g(ifm)%sflux_c(2,j)

         do ilp=1,npatch
            leaf_g(ifm)%ustar (1,j,ilp)  = leaf_g(ifm)%ustar (2,j,ilp)
            leaf_g(ifm)%rstar (1,j,ilp)  = leaf_g(ifm)%rstar (2,j,ilp)
            leaf_g(ifm)%tstar (1,j,ilp)  = leaf_g(ifm)%tstar (2,j,ilp)
            leaf_g(ifm)%cstar (1,j,ilp)  = leaf_g(ifm)%cstar (2,j,ilp)
            leaf_g(ifm)%zeta  (1,j,ilp)  = leaf_g(ifm)%zeta  (2,j,ilp)
            leaf_g(ifm)%ribulk(1,j,ilp)  = leaf_g(ifm)%ribulk(2,j,ilp)
         end do
      end do
   end if

   !----- Eastern Boundary ----------------------------------------------------------------!
   if (iand(ibcon,2) /= 0) then
      do j = ja, jz
         radiate_g(ifm)%albedt(m2,j) = radiate_g(ifm)%albedt(m2-1,j)
         radiate_g(ifm)%rlongup(m2,j)= radiate_g(ifm)%rlongup(m2-1,j)

         turb_g(ifm)%sflux_u(m2,j)   = turb_g(ifm)%sflux_u(m2-1,j)
         turb_g(ifm)%sflux_v(m2,j)   = turb_g(ifm)%sflux_v(m2-1,j)
         turb_g(ifm)%sflux_w(m2,j)   = turb_g(ifm)%sflux_w(m2-1,j)
         turb_g(ifm)%sflux_t(m2,j)   = turb_g(ifm)%sflux_t(m2-1,j)
         turb_g(ifm)%sflux_r(m2,j)   = turb_g(ifm)%sflux_r(m2-1,j)
         turb_g(ifm)%sflux_c(m2,j)   = turb_g(ifm)%sflux_c(m2-1,j)

         do ilp=1,npatch
            leaf_g(ifm)%ustar  (m2,j,ilp) = leaf_g(ifm)%ustar  (m2-1,j,ilp)
            leaf_g(ifm)%rstar  (m2,j,ilp) = leaf_g(ifm)%rstar  (m2-1,j,ilp)
            leaf_g(ifm)%tstar  (m2,j,ilp) = leaf_g(ifm)%tstar  (m2-1,j,ilp)
            leaf_g(ifm)%cstar  (m2,j,ilp) = leaf_g(ifm)%cstar  (m2-1,j,ilp)
            leaf_g(ifm)%zeta   (m2,j,ilp) = leaf_g(ifm)%zeta   (m2-1,j,ilp)
            leaf_g(ifm)%ribulk (m2,j,ilp) = leaf_g(ifm)%ribulk (m2-1,j,ilp)
         end do
      end do
   end if

   !----- Southern Boundary ---------------------------------------------------------------!
   if (jdim == 1 .and. iand(ibcon,4) /= 0) then
      do i = ia,iz
         radiate_g(ifm)%albedt(i,1) = radiate_g(ifm)%albedt(i,2)
         radiate_g(ifm)%rlongup(i,1)= radiate_g(ifm)%rlongup(i,2)

         turb_g(ifm)%sflux_u(i,1)   = turb_g(ifm)%sflux_u(i,2)
         turb_g(ifm)%sflux_v(i,1)   = turb_g(ifm)%sflux_v(i,2)
         turb_g(ifm)%sflux_w(i,1)   = turb_g(ifm)%sflux_w(i,2)
         turb_g(ifm)%sflux_t(i,1)   = turb_g(ifm)%sflux_t(i,2)
         turb_g(ifm)%sflux_r(i,1)   = turb_g(ifm)%sflux_r(i,2)
         turb_g(ifm)%sflux_c(i,1)   = turb_g(ifm)%sflux_c(i,2)

         do ilp=1,npatch
            leaf_g(ifm)%ustar  (i,1,ilp) = leaf_g(ifm)%ustar  (i,2,ilp)
            leaf_g(ifm)%rstar  (i,1,ilp) = leaf_g(ifm)%rstar  (i,2,ilp)
            leaf_g(ifm)%tstar  (i,1,ilp) = leaf_g(ifm)%tstar  (i,2,ilp)
            leaf_g(ifm)%cstar  (i,1,ilp) = leaf_g(ifm)%cstar  (i,2,ilp)
            leaf_g(ifm)%zeta   (i,1,ilp) = leaf_g(ifm)%zeta   (i,2,ilp)
            leaf_g(ifm)%ribulk (i,1,ilp) = leaf_g(ifm)%ribulk (i,2,ilp)
         end do
      end do
   end if


   !----- Northern Boundary ---------------------------------------------------------------!
   if (jdim == 1 .and. iand(ibcon,8) /= 0) then
      do i = ia,iz
         radiate_g(ifm)%albedt(i,m3) = radiate_g(ifm)%albedt(i,m3-1)
         radiate_g(ifm)%rlongup(i,m3)= radiate_g(ifm)%rlongup(i,m3-1)

         turb_g(ifm)%sflux_u(i,m3)   = turb_g(ifm)%sflux_u(i,m3-1)
         turb_g(ifm)%sflux_v(i,m3)   = turb_g(ifm)%sflux_v(i,m3-1)
         turb_g(ifm)%sflux_w(i,m3)   = turb_g(ifm)%sflux_w(i,m3-1)
         turb_g(ifm)%sflux_t(i,m3)   = turb_g(ifm)%sflux_t(i,m3-1)
         turb_g(ifm)%sflux_r(i,m3)   = turb_g(ifm)%sflux_r(i,m3-1)
         turb_g(ifm)%sflux_c(i,m3)   = turb_g(ifm)%sflux_c(i,m3-1)

         do ilp=1,npatch
            leaf_g(ifm)%ustar  (i,m3,ilp) = leaf_g(ifm)%ustar  (i,m3-1,ilp)
            leaf_g(ifm)%rstar  (i,m3,ilp) = leaf_g(ifm)%rstar  (i,m3-1,ilp)
            leaf_g(ifm)%tstar  (i,m3,ilp) = leaf_g(ifm)%tstar  (i,m3-1,ilp)
            leaf_g(ifm)%cstar  (i,m3,ilp) = leaf_g(ifm)%cstar  (i,m3-1,ilp)
            leaf_g(ifm)%zeta   (i,m3,ilp) = leaf_g(ifm)%zeta   (i,m3-1,ilp)
            leaf_g(ifm)%ribulk (i,m3,ilp) = leaf_g(ifm)%ribulk (i,m3-1,ilp)
         end do

      end do
   end if

   !----- Southwestern corner -------------------------------------------------------------!
   if (iand(ibcon,5) /= 0 .or. (iand(ibcon,1) /= 0 .and. jdim == 0)) then
      ic=1
      jc=1
      ici=2
      jci=1+jdim

      radiate_g(ifm)%albedt(ic,jc) = radiate_g(ifm)%albedt(ici,jci)
      radiate_g(ifm)%rlongup(ic,jc)= radiate_g(ifm)%rlongup(ici,jci)

      turb_g(ifm)%sflux_u(ic,jc)   = turb_g(ifm)%sflux_u(ici,jci)
      turb_g(ifm)%sflux_v(ic,jc)   = turb_g(ifm)%sflux_v(ici,jci)
      turb_g(ifm)%sflux_w(ic,jc)   = turb_g(ifm)%sflux_w(ici,jci)
      turb_g(ifm)%sflux_t(ic,jc)   = turb_g(ifm)%sflux_t(ici,jci)
      turb_g(ifm)%sflux_r(ic,jc)   = turb_g(ifm)%sflux_r(ici,jci)
      turb_g(ifm)%sflux_c(ic,jc)   = turb_g(ifm)%sflux_c(ici,jci)

      do ilp=1,npatch
         leaf_g(ifm)%ustar  (ic,jc,ilp) = leaf_g(ifm)%ustar  (ici,jci,ilp)
         leaf_g(ifm)%rstar  (ic,jc,ilp) = leaf_g(ifm)%rstar  (ici,jci,ilp)
         leaf_g(ifm)%tstar  (ic,jc,ilp) = leaf_g(ifm)%tstar  (ici,jci,ilp)
         leaf_g(ifm)%cstar  (ic,jc,ilp) = leaf_g(ifm)%cstar  (ici,jci,ilp)
         leaf_g(ifm)%zeta   (ic,jc,ilp) = leaf_g(ifm)%zeta   (ici,jci,ilp)
         leaf_g(ifm)%ribulk (ic,jc,ilp) = leaf_g(ifm)%ribulk (ici,jci,ilp)
      end do

   end if

   !----- Southeastern corner -------------------------------------------------------------!
   if (iand(ibcon,6) /= 0 .or. (iand(ibcon,2) /= 0 .and. jdim == 0)) then
      ic=m2
      jc=1
      ici=m2-1
      jci=1+jdim

      radiate_g(ifm)%albedt(ic,jc) = radiate_g(ifm)%albedt(ici,jci)
      radiate_g(ifm)%rlongup(ic,jc)= radiate_g(ifm)%rlongup(ici,jci)

      turb_g(ifm)%sflux_u(ic,jc)   = turb_g(ifm)%sflux_u(ici,jci)
      turb_g(ifm)%sflux_v(ic,jc)   = turb_g(ifm)%sflux_v(ici,jci)
      turb_g(ifm)%sflux_w(ic,jc)   = turb_g(ifm)%sflux_w(ici,jci)
      turb_g(ifm)%sflux_t(ic,jc)   = turb_g(ifm)%sflux_t(ici,jci)
      turb_g(ifm)%sflux_r(ic,jc)   = turb_g(ifm)%sflux_r(ici,jci)
      turb_g(ifm)%sflux_c(ic,jc)   = turb_g(ifm)%sflux_c(ici,jci)

      do ilp=1,npatch
         leaf_g(ifm)%ustar  (ic,jc,ilp) = leaf_g(ifm)%ustar  (ici,jci,ilp)
         leaf_g(ifm)%rstar  (ic,jc,ilp) = leaf_g(ifm)%rstar  (ici,jci,ilp)
         leaf_g(ifm)%tstar  (ic,jc,ilp) = leaf_g(ifm)%tstar  (ici,jci,ilp)
         leaf_g(ifm)%cstar  (ic,jc,ilp) = leaf_g(ifm)%cstar  (ici,jci,ilp)
         leaf_g(ifm)%zeta   (ic,jc,ilp) = leaf_g(ifm)%zeta   (ici,jci,ilp)
         leaf_g(ifm)%ribulk (ic,jc,ilp) = leaf_g(ifm)%ribulk (ici,jci,ilp)
      end do
   end if
  
   !----- Northwestern corner -------------------------------------------------------------!
   if (iand(ibcon,9) /= 0 .or. (iand(ibcon,1) /= 0 .and. jdim == 0)) then
      ic=1
      jc=m3
      ici=2
      jci=m3-jdim

      radiate_g(ifm)%albedt(ic,jc) = radiate_g(ifm)%albedt(ici,jci)
      radiate_g(ifm)%rlongup(ic,jc)= radiate_g(ifm)%rlongup(ici,jci)

      turb_g(ifm)%sflux_u(ic,jc)   = turb_g(ifm)%sflux_u(ici,jci)
      turb_g(ifm)%sflux_v(ic,jc)   = turb_g(ifm)%sflux_v(ici,jci)
      turb_g(ifm)%sflux_w(ic,jc)   = turb_g(ifm)%sflux_w(ici,jci)
      turb_g(ifm)%sflux_t(ic,jc)   = turb_g(ifm)%sflux_t(ici,jci)
      turb_g(ifm)%sflux_r(ic,jc)   = turb_g(ifm)%sflux_r(ici,jci)
      turb_g(ifm)%sflux_c(ic,jc)   = turb_g(ifm)%sflux_c(ici,jci)

      do ilp=1,npatch
         leaf_g(ifm)%ustar  (ic,jc,ilp) = leaf_g(ifm)%ustar  (ici,jci,ilp)
         leaf_g(ifm)%rstar  (ic,jc,ilp) = leaf_g(ifm)%rstar  (ici,jci,ilp)
         leaf_g(ifm)%tstar  (ic,jc,ilp) = leaf_g(ifm)%tstar  (ici,jci,ilp)
         leaf_g(ifm)%cstar  (ic,jc,ilp) = leaf_g(ifm)%cstar  (ici,jci,ilp)
         leaf_g(ifm)%zeta   (ic,jc,ilp) = leaf_g(ifm)%zeta   (ici,jci,ilp)
         leaf_g(ifm)%ribulk (ic,jc,ilp) = leaf_g(ifm)%ribulk (ici,jci,ilp)
      end do
   end if

   !----- Northeastern corner -------------------------------------------------------------!
   if (iand(ibcon,10) /= 0 .or. (iand(ibcon,2) /= 0 .and. jdim == 0)) then
      ic=m2
      jc=m3
      ici=m2-1
      jci=m3-jdim

      radiate_g(ifm)%albedt(ic,jc) = radiate_g(ifm)%albedt(ici,jci)
      radiate_g(ifm)%rlongup(ic,jc)= radiate_g(ifm)%rlongup(ici,jci)

      turb_g(ifm)%sflux_u(ic,jc)   = turb_g(ifm)%sflux_u(ici,jci)
      turb_g(ifm)%sflux_v(ic,jc)   = turb_g(ifm)%sflux_v(ici,jci)
      turb_g(ifm)%sflux_w(ic,jc)   = turb_g(ifm)%sflux_w(ici,jci)
      turb_g(ifm)%sflux_t(ic,jc)   = turb_g(ifm)%sflux_t(ici,jci)
      turb_g(ifm)%sflux_r(ic,jc)   = turb_g(ifm)%sflux_r(ici,jci)
      turb_g(ifm)%sflux_c(ic,jc)   = turb_g(ifm)%sflux_c(ici,jci)

      do ilp=1,npatch
         leaf_g(ifm)%ustar  (ic,jc,ilp) = leaf_g(ifm)%ustar  (ici,jci,ilp)
         leaf_g(ifm)%rstar  (ic,jc,ilp) = leaf_g(ifm)%rstar  (ici,jci,ilp)
         leaf_g(ifm)%tstar  (ic,jc,ilp) = leaf_g(ifm)%tstar  (ici,jci,ilp)
         leaf_g(ifm)%cstar  (ic,jc,ilp) = leaf_g(ifm)%cstar  (ici,jci,ilp)
         leaf_g(ifm)%zeta   (ic,jc,ilp) = leaf_g(ifm)%zeta   (ici,jci,ilp)
         leaf_g(ifm)%ribulk (ic,jc,ilp) = leaf_g(ifm)%ribulk (ici,jci,ilp)
      end do
   end if


   return
end subroutine transfer_ed2leaf
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
subroutine copy_avgvars_to_leaf(ifm)

   use ed_state_vars , only : edgrid_g           & ! structure
                            , edtype             & ! structure
                            , polygontype        & ! structure
                            , sitetype           & ! structure
                            , patchtype          ! ! structure
   use mem_leaf      , only : leaf_g             ! ! intent(inout)
   use mem_edcp      , only : co2_offset         & ! intent(in)
                            , atm_co2_min        ! ! intent(in)
   use mem_grid      , only : nzg                & ! intent(in)
                            , nzs                ! ! intent(in)
   use rconstants    , only : t3ple              & ! intent(in)
                            , wdns               ! ! intent(in)
   use therm_lib     , only : alvl               & ! intent(in)
                            , alvi               & ! intent(in)
                            , uint2tl            & ! intent(in)
                            , uextcm2tl          & ! intent(in)
                            , press2exner        & ! intent(in)
                            , extheta2temp       ! ! intent(in)
   use soil_coms     , only : soil               & ! intent(in)
                            , tiny_sfcwater_mass ! ! intent(in)
   use ed_misc_coms  , only : frqsum             ! ! intent(in)
   use ed_max_dims   , only : n_pft              & ! intent(in)
                            , n_dbh              ! ! intent(in)
   implicit none
   
   !----- Argument ------------------------------------------------------------------------!
   integer, intent(in)  :: ifm
   !----- Local variables -----------------------------------------------------------------!
   type(edtype)     , pointer :: cgrid
   type(polygontype), pointer :: cpoly
   type(sitetype)   , pointer :: csite
   type(patchtype)  , pointer :: cpatch
   integer                    :: ipy
   integer                    :: isi
   integer                    :: ipa
   integer                    :: ico
   integer                    :: ix
   integer                    :: iy
   integer                    :: ilp
   integer                    :: k
   integer                    :: idbh
   integer                    :: ipft
   integer                    :: nsoil
   real                       :: site_area_i
   real                       :: ground_temp
   real                       :: ground_fliq
   real                       :: veg_temp
   real                       :: veg_fliq
   real                       :: can_temp
   real                       :: can_exner
   !---------------------------------------------------------------------------------------!

   !----- Set the pointers ----------------------------------------------------------------!
   cgrid => edgrid_g(ifm)
   !---------------------------------------------------------------------------------------!



   !---------------------------------------------------------------------------------------!
   !      Loop over all polygons.                                                          !
   !---------------------------------------------------------------------------------------!
   polyloop: do ipy=1,cgrid%npolygons
      cpoly => cgrid%polygon(ipy)

      !----- Copy the index of this polygons that correspond to the BRAMS grid. -----------!
      ix = cgrid%ilon(ipy)
      iy = cgrid%ilat(ipy)
      !------------------------------------------------------------------------------------!



      !------------------------------------------------------------------------------------!
      !      Copy the ED site-level averages to leaf_g structure "patches".                !
      !------------------------------------------------------------------------------------!
      siteloop: do isi = 1,cpoly%nsites
         !----- Pointer for the current site. ---------------------------------------------!
         csite => cpoly%site(isi)
         site_area_i = 1. / sum(csite%area)
         !---------------------------------------------------------------------------------!


         !----- Leaf "patch" is offset by 1 because the first is water. -------------------!
         ilp = isi + 1
         !---------------------------------------------------------------------------------!


         !---------------------------------------------------------------------------------!
         !     Copy the soil information.                                                  !
         !---------------------------------------------------------------------------------!
         do k=1,nzg
            leaf_g(ifm)%soil_text  (k,ix,iy,ilp) = real(cpoly%ntext_soil(k,isi))
            leaf_g(ifm)%soil_energy(k,ix,iy,ilp) = cpoly%avg_soil_energy(k,isi)
            leaf_g(ifm)%soil_water (k,ix,iy,ilp) = cpoly%avg_soil_water (k,isi)
         end do
         leaf_g(ifm)%psibar_10d (ix,iy,ilp) = 1.0
         leaf_g(ifm)%soil_color(ix,iy,ilp)  = real(cpoly%ncol_soil(isi))
         !---------------------------------------------------------------------------------!


         !---------------------------------------------------------------------------------!
         !    Site-level Surface water properties are always merged into one layer, 1,     !
         ! so we copy all the information that may exist to the first layer and make the   !
         ! others zero.  In case there is nothing to copy, make it empty.                  !
         !---------------------------------------------------------------------------------!
         if (cgrid%avg_sfcw_mass  (isi) > tiny_sfcwater_mass) then
            leaf_g(ifm)%sfcwater_nlev     (ix,iy,ilp) = 1.
            leaf_g(ifm)%sfcwater_energy (1,ix,iy,ilp) = cgrid%avg_sfcw_energy(isi)
            leaf_g(ifm)%sfcwater_mass   (1,ix,iy,ilp) = cgrid%avg_sfcw_mass  (isi)
            leaf_g(ifm)%sfcwater_depth  (1,ix,iy,ilp) = cgrid%avg_sfcw_depth (isi)
         else
            leaf_g(ifm)%sfcwater_nlev     (ix,iy,ilp) = 0.
            leaf_g(ifm)%sfcwater_energy (1,ix,iy,ilp) = 0.
            leaf_g(ifm)%sfcwater_mass   (1,ix,iy,ilp) = 0.
            leaf_g(ifm)%sfcwater_depth  (1,ix,iy,ilp) = 0.
         end if
         do k=2,nzs
            leaf_g(ifm)%sfcwater_energy (k,ix,iy,ilp) = 0.
            leaf_g(ifm)%sfcwater_mass   (k,ix,iy,ilp) = 0.
            leaf_g(ifm)%sfcwater_depth  (k,ix,iy,ilp) = 0.
         end do
         !---------------------------------------------------------------------------------!



         !---------------------------------------------------------------------------------!
         !      Update vegetation properties.                                              !
         !---------------------------------------------------------------------------------!
         leaf_g(ifm)%veg_water   (ix,iy,ilp)   = cpoly%avg_leaf_water  (isi)               &
                                               + cpoly%avg_wood_water  (isi)
         leaf_g(ifm)%veg_hcap    (ix,iy,ilp)   = cpoly%avg_leaf_hcap   (isi)               &
                                               + cpoly%avg_wood_hcap   (isi)
         leaf_g(ifm)%veg_energy  (ix,iy,ilp)   = cpoly%avg_leaf_energy (isi)               &
                                               + cpoly%avg_wood_energy (isi)
         leaf_g(ifm)%veg_lai     (ix,iy,ilp)   = cpoly%lai(isi)
         leaf_g(ifm)%veg_tai     (ix,iy,ilp)   = cpoly%lai(isi) + cgrid%wai(isi)
         !---------------------------------------------------------------------------------!



         !----- Fill above ground biomass by integrating all PFTs and DBH classes. --------!
         leaf_g(ifm)%veg_agb(ix,iy,ilp)       = 0.
         do idbh=1,n_dbh
            do ipft=1,n_pft
               leaf_g(ifm)%veg_agb(ix,iy,ilp) = leaf_g(ifm)%veg_agb(ix,iy,ilp)             &
                                              + cpoly%agb(ipft,idbh,isi)
            end do
         end do
         !---------------------------------------------------------------------------------!



         !---------------------------------------------------------------------------------!
         !      Update canopy air properties.                                              !
         !---------------------------------------------------------------------------------!
         leaf_g(ifm)%can_theta  (ix,iy,ilp) = cpoly%avg_can_theta(isi)
         leaf_g(ifm)%can_theiv  (ix,iy,ilp) = cpoly%avg_can_theiv(isi)
         leaf_g(ifm)%can_co2    (ix,iy,ilp) = max( atm_co2_min                             &
                                                 , cpoly%avg_can_co2(isi) - co2_offset)
         leaf_g(ifm)%can_prss   (ix,iy,ilp) = cpoly%avg_can_prss(isi)
         !----- ED uses specific humidity, converting it to mixing ratio. -----------------!
         leaf_g(ifm)%can_rvap   (ix,iy,ilp) = cpoly%avg_can_shv(isi)                       &
                                            / (1.-cpoly%avg_can_shv(isi))
         !---------------------------------------------------------------------------------!



         !---------------------------------------------------------------------------------!
         !     Temperature and liquid fraction of surfaces.  We need them to find the      !
         ! mean latent heat of vapourisation between leaves/ground and the canopy air      !
         ! space.                                                                          !
         !---------------------------------------------------------------------------------!
         !----- Ground temperature. -------------------------------------------------------!
         if (leaf_g(ifm)%sfcwater_nlev(ix,iy,ilp) == 0.) then
            !------ There is no temporary surface water.  Use top soil temperature. -------!
            nsoil = cpoly%ntext_soil(nzg,isi)
            call uextcm2tl(cgrid%avg_soil_energy(nzg,isi)                                  &
                          ,cgrid%avg_soil_water(nzg,isi) * wdns,soil(nsoil)%slcpd          &
                          ,ground_temp,ground_fliq )
            !------------------------------------------------------------------------------!
         else
            !------ There is a temporary surface water.  Use average temperature. ---------!
            call uint2tl(cgrid%avg_sfcw_energy(isi),ground_temp,ground_fliq)
            !------------------------------------------------------------------------------!
         end if
         !----- Vegetation temperature.  Here we must check if there are plants. ----------!
         if (leaf_g(ifm)%veg_hcap(ix,iy,ilp) > 0.) then
            !----- There is some plant here. ----------------------------------------------!
            call uextcm2tl(leaf_g(ifm)%veg_energy(ix,iy,ilp)                               &
                          ,leaf_g(ifm)%veg_water (ix,iy,ilp)                               &
                          ,leaf_g(ifm)%veg_hcap  (ix,iy,ilp)                               &
                          ,veg_temp,veg_fliq )
            !------------------------------------------------------------------------------!
         else
            !----- Site is empty.  Use canopy air space instead. --------------------------!
            can_exner = press2exner(cpoly%avg_can_prss(isi))
            can_temp  = extheta2temp(can_exner,leaf_g(ifm)%can_theta(ix,iy,ilp))
            veg_temp  = can_temp
            if (veg_temp == t3ple) then
               veg_fliq = 0.5
            elseif (veg_temp > t3ple) then
               veg_fliq = 1.0
            else
               veg_fliq = 0.0
            end if
            !------------------------------------------------------------------------------!
         end if
         !---------------------------------------------------------------------------------!



         !---------------------------------------------------------------------------------!
         !     Copy the fluxes, which will be used for output only.                        !
         !---------------------------------------------------------------------------------!
         leaf_g(ifm)%sensible_gc(ix,iy,ilp) = cpoly%avg_sensible_gc(isi)
         leaf_g(ifm)%sensible_vc(ix,iy,ilp) = ( cpoly%avg_sensible_lc(isi)                 &
                                              + cpoly%avg_sensible_wc(isi) )
         leaf_g(ifm)%evap_gc    (ix,iy,ilp) = cpoly%avg_vapor_gc(isi)                      &
                                            * ( ground_fliq * alvl(ground_temp)            &
                                              + (1.0 - ground_fliq) * alvi(ground_temp) )
         leaf_g(ifm)%evap_vc    (ix,iy,ilp) = ( cpoly%avg_vapor_lc(isi)                    &
                                              + cpoly%avg_vapor_wc(isi) )                  &
                                            * ( veg_fliq * alvl(veg_temp)                  &
                                              + (1.0 - veg_fliq) * alvi(veg_temp) )
         !----- Transpiration only happens from liquid phase to vapour. -------------------!
         leaf_g(ifm)%transp     (ix,iy,ilp) = cpoly%avg_transp(isi) * alvl(veg_temp)
         !---------------------------------------------------------------------------------!



         !------ Carbon fluxes don't have polygon level, compute the average here. --------!
         leaf_g(ifm)%gpp        (ix,iy,ilp) = sum(csite%area * csite%co2budget_gpp     )   &
                                            * site_area_i
         leaf_g(ifm)%plresp     (ix,iy,ilp) = sum(csite%area * csite%co2budget_plresp  )   &
                                            * site_area_i
         leaf_g(ifm)%resphet    (ix,iy,ilp) = sum(csite%area * csite%co2budget_rh      )   &
                                            * site_area_i
         !---------------------------------------------------------------------------------!
      end do siteloop
      !------------------------------------------------------------------------------------!
   end do polyloop
   !---------------------------------------------------------------------------------------!


   return
end subroutine copy_avgvars_to_leaf
!==========================================================================================!
!==========================================================================================!

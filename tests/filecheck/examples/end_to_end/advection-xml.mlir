// Test the XML frontend → optimizer → Fortran pipeline for the advection
// example.  Exercises: four distinct schemes in one suite, a scheme that
// appears twice in the suite XML (apply_constituent_tendencies), host/module
// metadata files, and 3-D array arguments.
//
// Note: duplicate scheme entries are deduplicated in the suite cap — only one
// call to apply_constituent_tendencies_run is emitted even though the scheme
// appears twice in the XML.
//
// RUN: python3 -m xdsl_ccpp.frontend.ccpp_xml --suites examples/advection/cld_suite.xml --scheme-files examples/advection/const_indices.meta,examples/advection/cld_liq.meta,examples/advection/cld_ice.meta,examples/advection/apply_constituent_tendencies.meta --host-files examples/advection/test_host_data.meta,examples/advection/test_host.meta,examples/advection/test_host_mod.meta | python3 -m xdsl_ccpp.tools.ccpp_opt -p generate-meta-cap,generate-meta-kinds,generate-suite-cap,generate-ccpp-cap,generate-kinds,strip-ccpp -t ftn | python3 -m filecheck %s

// CHECK-LABEL: // FILE: cld_suite_cap.F90
// CHECK-LABEL: module cld_suite_cap
// CHECK:         use ccpp_kinds
// CHECK-NEXT:    use apply_constituent_tendencies, only: apply_constituent_tendencies_run
// CHECK-NEXT:    use ccpp_constituent_prop_mod, only: ccpp_constituent_properties_t
// CHECK-NEXT:    use cld_ice, only: cld_ice_final
// CHECK-NEXT:    use cld_ice, only: cld_ice_init
// CHECK-NEXT:    use cld_ice, only: cld_ice_register
// CHECK-NEXT:    use cld_ice, only: cld_ice_run
// CHECK-NEXT:    use cld_liq, only: cld_liq_init
// CHECK-NEXT:    use cld_liq, only: cld_liq_register
// CHECK-NEXT:    use cld_liq, only: cld_liq_run
// CHECK-NEXT:    use const_indices, only: const_indices_init
// CHECK-NEXT:    use const_indices, only: const_indices_run
// CHECK-NEXT:    use test_host_data, only: const_index
// CHECK-NEXT:    use test_host_data, only: const_inds
// CHECK-NEXT:    use test_host_data, only: const_std_name
// CHECK-NEXT:    use test_host_data, only: num_consts
// CHECK-NEXT:    use test_host_data, only: std_name_array
// CHECK-NEXT:    use test_host_mod, only: dt
// CHECK-NEXT:    use test_host_mod, only: index_qv
// CHECK-NEXT:    use test_host_mod, only: phys_state
// CHECK-NEXT:    use test_host_mod, only: pver
// CHECK-NEXT:    use test_host_mod, only: tfreeze
// CHECK:         implicit none
// CHECK-NEXT:    private
// CHECK:         character(len=16) :: ccpp_suite_state = 'uninitialized'
// CHECK-NEXT:    character(len=16), parameter :: const_in_time_step = 'in_time_step'
// CHECK-NEXT:    character(len=16), parameter :: const_initialized = 'initialized'
// CHECK-NEXT:    character(len=16), parameter :: const_uninitialized = 'uninitialized'
// CHECK-NEXT:    real(kind=kind_phys) :: tcld
// CHECK-NEXT:    type(ccpp_constituent_properties_t), private, allocatable :: ccpp_constituents(:)
// CHECK-NEXT:    logical, private :: ccpp_constituents_initialized = .false.
// CHECK-NEXT:    private :: ccpp_create_constituent_array
// CHECK-NEXT:    public :: cld_suite_constituents_num_consts
// CHECK-NEXT:    public :: cld_suite_constituents_const_name
// CHECK-NEXT:    public :: cld_suite_constituents_copy_const
// CHECK-NEXT:    public :: cld_suite_suite_register
// CHECK-NEXT:    public :: cld_suite_suite_initialize
// CHECK-NEXT:    public :: cld_suite_suite_finalize
// CHECK-NEXT:    public :: cld_suite_suite_physics
// CHECK-NEXT:    public :: cld_suite_suite_timestep_initial
// CHECK-NEXT:    public :: cld_suite_suite_timestep_final
// CHECK:       CONTAINS
// CHECK-LABEL:   subroutine ccpp_create_constituent_array(errmsg, errflg)
// CHECK:           ! Allocate and fill the constituent property array for this suite
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK-NEXT:      integer :: index
// CHECK-NEXT:      allocate(ccpp_constituents(2))
// CHECK-NEXT:      index = 0
// CHECK-NEXT:      errmsg = ''
// CHECK-NEXT:      errflg = 0
// CHECK-NEXT:      index = index + 1
// CHECK-NEXT:      if (errflg == 0) then
// CHECK-NEXT:        call ccpp_constituents(index)%instantiate(std_name='cloud_liquid_dry_mixing_ratio',         &
// CHECK-NEXT:      long_name='Cloud liquid dry mixing ratio', units='kg kg-1',                                   &
// CHECK-NEXT:      vertical_dim='vertical_layer_dimension', advected=.true., errcode=errflg, errmsg=errmsg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      index = index + 1
// CHECK-NEXT:      if (errflg == 0) then
// CHECK-NEXT:        call ccpp_constituents(index)%instantiate(std_name='cloud_ice_dry_mixing_ratio',            &
// CHECK-NEXT:      long_name='Cloud ice dry mixing ratio', units='kg kg-1',                                      &
// CHECK-NEXT:      vertical_dim='vertical_layer_dimension', advected=.true., errcode=errflg, errmsg=errmsg,      &
// CHECK-NEXT:      default_value=0.0_kind_phys)
// CHECK-NEXT:      end if
// CHECK-NEXT:      ccpp_constituents_initialized = .true.
// CHECK-NEXT:    end subroutine ccpp_create_constituent_array
// CHECK:         integer function cld_suite_constituents_num_consts(errmsg, errflg)
// CHECK-NEXT:      ! Return the number of constituents for this suite
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK-NEXT:      errmsg = ''
// CHECK-NEXT:      errflg = 0
// CHECK-NEXT:      if (.not. ccpp_constituents_initialized) then
// CHECK-NEXT:        call ccpp_create_constituent_array(errflg=errflg, errmsg=errmsg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      cld_suite_constituents_num_consts = 2
// CHECK-NEXT:    end function cld_suite_constituents_num_consts
// CHECK-LABEL:   subroutine cld_suite_constituents_const_name(index, name_out, errmsg, errflg)
// CHECK:           ! Return the name of constituent, <index>
// CHECK-NEXT:      integer, intent(in) :: index
// CHECK-NEXT:      character(len=*), intent(out) :: name_out
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK-NEXT:      errflg = 0
// CHECK-NEXT:      errmsg = ''
// CHECK-NEXT:      if (.not. ccpp_constituents_initialized) then
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:        errmsg = "constituent properties not initialized for suite, cld_suite"
// CHECK-NEXT:        return
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (index < 1) then
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:        write(errmsg, '(a,i0,a)') 'ERROR: index (',index,') too small, must be >= 1'
// CHECK-NEXT:        return
// CHECK-NEXT:      else if (index > size(ccpp_constituents)) then
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:        write(errmsg, '(2(a,i0))') 'ERROR: index (',index,') too large, must be <= ',               &
// CHECK-NEXT:      size(ccpp_constituents)
// CHECK-NEXT:        return
// CHECK-NEXT:      end if
// CHECK-NEXT:      call ccpp_constituents(index)%standard_name(std_name=name_out, errcode=errflg, errmsg=errmsg)
// CHECK-NEXT:    end subroutine cld_suite_constituents_const_name
// CHECK-LABEL:   subroutine cld_suite_constituents_copy_const(index, cnst_out, errmsg, errflg)
// CHECK:           ! Copy the properties of constituent, <index>
// CHECK-NEXT:      integer, intent(in) :: index
// CHECK-NEXT:      type(ccpp_constituent_properties_t), intent(out) :: cnst_out
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK-NEXT:      errflg = 0
// CHECK-NEXT:      errmsg = ''
// CHECK-NEXT:      if (.not. ccpp_constituents_initialized) then
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:        errmsg = "constituent properties not initialized for suite, cld_suite"
// CHECK-NEXT:        return
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (index < 1) then
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:        write(errmsg, '(a,i0,a)') 'ERROR: index (',index,') too small, must be >= 1'
// CHECK-NEXT:        return
// CHECK-NEXT:      else if (index > size(ccpp_constituents)) then
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:        write(errmsg, '(2(a,i0))') 'ERROR: index (',index,') too large, must be <= ',               &
// CHECK-NEXT:      size(ccpp_constituents)
// CHECK-NEXT:        return
// CHECK-NEXT:      end if
// CHECK-NEXT:      cnst_out = ccpp_constituents(index)
// CHECK-NEXT:    end subroutine cld_suite_constituents_copy_const
// CHECK-LABEL:   subroutine cld_suite_suite_register(dyn_const, dyn_const_ice, errmsg, errflg)
// CHECK:           type(ccpp_constituent_properties_t), allocatable, intent(out) :: dyn_const(:)
// CHECK-NEXT:      type(ccpp_constituent_properties_t), allocatable, intent(out) :: dyn_const_ice(:)
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (.NOT. (const_uninitialized .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in cld_suite_register"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call cld_liq_register(dyn_const=dyn_const, errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call cld_ice_register(dyn_const_ice=dyn_const_ice, errmsg=errmsg, errcode=errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine cld_suite_suite_register
// CHECK-LABEL:   subroutine cld_suite_suite_initialize(cld_liq_array, cld_ice_array, errmsg, errflg)
// CHECK:           real(kind=kind_phys), intent(out) :: cld_liq_array(:, :)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: cld_ice_array(:, :)
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (.NOT. (const_uninitialized .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in cld_suite_initialize"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call const_indices_init(const_std_name=const_std_name, num_consts=num_consts,               &
// CHECK-NEXT:          test_stdname_array=std_name_array, const_index=const_index, const_inds=const_inds,        &
// CHECK-NEXT:          errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call cld_liq_init(tfreeze=tfreeze, cld_liq_array=cld_liq_array, tcld=tcld, errmsg=errmsg,   &
// CHECK-NEXT:          errflg=errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call cld_ice_init(tfreeze=tfreeze, cld_ice_array=cld_ice_array, errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      ccpp_suite_state = const_initialized
// CHECK-NEXT:    end subroutine cld_suite_suite_initialize
// CHECK-LABEL:   subroutine cld_suite_suite_finalize(errmsg, errflg)
// CHECK:           character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (.NOT. (const_initialized .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in cld_suite_finalize"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call cld_ice_final(errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      ccpp_suite_state = const_uninitialized
// CHECK-NEXT:    end subroutine cld_suite_suite_finalize
// CHECK-LABEL:   subroutine cld_suite_suite_physics(col_start, col_end, cld_liq_tend, const_tend, const,         &
// CHECK:           cld_ice_array, errmsg, errflg)
// CHECK-NEXT:      integer, intent(in) :: col_start
// CHECK-NEXT:      integer, intent(in) :: col_end
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: cld_liq_tend(:, :)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: const_tend(:, :, :)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: const(:, :, :)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: cld_ice_array(:, :)
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK-NEXT:      integer :: ccpp_ncol
// CHECK:           errflg = 0
// CHECK-NEXT:      ccpp_ncol = col_end - col_start + 1
// CHECK-NEXT:      if (.NOT. (const_in_time_step .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in cld_suite_physics"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call const_indices_run(const_std_name=const_std_name, num_consts=num_consts,                &
// CHECK-NEXT:          test_stdname_array=std_name_array, const_index=const_index, const_inds=const_inds,        &
// CHECK-NEXT:          errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call cld_liq_run(ncol=ccpp_ncol, timestep=dt, tcld=tcld,                                    &
// CHECK-NEXT:          temp=phys_state%Temp(col_start:col_end, 1:pver), qv=phys_state%q(col_start:col_end,       &
// CHECK-NEXT:          1:pver, index_qv), ps=phys_state%ps(col_start:col_end), cld_liq_tend=cld_liq_tend,        &
// CHECK-NEXT:          errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call apply_constituent_tendencies_run(const_tend=const_tend, const=const, errcode=errflg,   &
// CHECK-NEXT:          errmsg=errmsg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call cld_ice_run(ncol=ccpp_ncol, timestep=dt, temp=phys_state%Temp(col_start:col_end,       &
// CHECK-NEXT:          1:pver), qv=phys_state%q(col_start:col_end, 1:pver, index_qv),                            &
// CHECK-NEXT:          ps=phys_state%ps(col_start:col_end), cld_ice_array=cld_ice_array, errmsg=errmsg,          &
// CHECK-NEXT:          errflg=errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call apply_constituent_tendencies_run(const_tend=const_tend, const=const, errcode=errflg,   &
// CHECK-NEXT:          errmsg=errmsg)
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine cld_suite_suite_physics
// CHECK-LABEL:   subroutine cld_suite_suite_timestep_initial(errmsg, errflg)
// CHECK:           character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (.NOT. (const_initialized .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in cld_suite_timestep_initial"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      ccpp_suite_state = const_in_time_step
// CHECK-NEXT:    end subroutine cld_suite_suite_timestep_initial
// CHECK-LABEL:   subroutine cld_suite_suite_timestep_final(errmsg, errflg)
// CHECK:           character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (.NOT. (const_in_time_step .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in cld_suite_timestep_final"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      ccpp_suite_state = const_initialized
// CHECK-NEXT:    end subroutine cld_suite_suite_timestep_final
// CHECK-NEXT:  end module cld_suite_cap
// CHECK:       // -----
// CHECK-LABEL: // FILE: cld_ccpp_cap.F90
// CHECK-LABEL: module cld_ccpp_cap
// CHECK:         use ccpp_kinds
// CHECK-NEXT:    use ccpp_constituent_prop_mod, only: ccpp_constituent_properties_t
// CHECK-NEXT:    use ccpp_constituent_prop_mod, only: ccpp_model_constituents_t
// CHECK-NEXT:    use cld_suite_cap, only: cld_suite_constituents_const_name
// CHECK-NEXT:    use cld_suite_cap, only: cld_suite_constituents_copy_const
// CHECK-NEXT:    use cld_suite_cap, only: cld_suite_constituents_num_consts
// CHECK-NEXT:    use cld_suite_cap, only: cld_suite_suite_finalize
// CHECK-NEXT:    use cld_suite_cap, only: cld_suite_suite_initialize
// CHECK-NEXT:    use cld_suite_cap, only: cld_suite_suite_physics
// CHECK-NEXT:    use cld_suite_cap, only: cld_suite_suite_register
// CHECK-NEXT:    use cld_suite_cap, only: cld_suite_suite_timestep_final
// CHECK-NEXT:    use cld_suite_cap, only: cld_suite_suite_timestep_initial
// CHECK-NEXT:    use test_host_mod, only: pver
// CHECK:         implicit none
// CHECK-NEXT:    private
// CHECK:         character(len=9), parameter :: str_cld_suite = 'cld_suite'
// CHECK-NEXT:    character(len=7), parameter :: str_physics = 'physics'
// CHECK-NEXT:    type(ccpp_model_constituents_t), target :: Cld_constituents_obj
// CHECK-NEXT:    type(ccpp_constituent_properties_t), allocatable, target :: cld_suite_dynamic_constituents(:)
// CHECK-NEXT:    character(len=29) :: Cld_model_const_stdnames(2) = (/ "cloud_ice_dry_mixing_ratio   ",          &
// CHECK-NEXT:    "cloud_liquid_dry_mixing_ratio" /)
// CHECK-NEXT:    integer :: Cld_model_const_indices(2) = -1
// CHECK-NEXT:    public :: Cld_ccpp_register_constituents
// CHECK-NEXT:    public :: Cld_ccpp_initialize_constituents
// CHECK-NEXT:    public :: Cld_ccpp_number_constituents
// CHECK-NEXT:    public :: Cld_ccpp_is_scheme_constituent
// CHECK-NEXT:    public :: Cld_ccpp_gather_constituents
// CHECK-NEXT:    public :: Cld_ccpp_update_constituents
// CHECK-NEXT:    public :: Cld_ccpp_deallocate_dynamic_constituents
// CHECK-NEXT:    public :: Cld_constituents_array
// CHECK-NEXT:    public :: Cld_advected_constituents_array
// CHECK-NEXT:    public :: Cld_model_const_properties
// CHECK-NEXT:    public :: Cld_const_get_index
// CHECK-NEXT:    public :: Cld_ccpp_physics_register
// CHECK-NEXT:    public :: Cld_ccpp_physics_initialize
// CHECK-NEXT:    public :: Cld_ccpp_physics_finalize
// CHECK-NEXT:    public :: Cld_ccpp_physics_timestep_initial
// CHECK-NEXT:    public :: Cld_ccpp_physics_timestep_final
// CHECK-NEXT:    public :: Cld_ccpp_physics_run
// CHECK-NEXT:    public :: ccpp_physics_suite_list
// CHECK-NEXT:    public :: ccpp_physics_suite_part_list
// CHECK-NEXT:    public :: ccpp_physics_suite_variables
// CHECK:       CONTAINS
// CHECK-LABEL:   subroutine Cld_ccpp_physics_register(suite_name, errmsg, errflg)
// CHECK:           character(len=*), intent(in) :: suite_name
// CHECK-NEXT:      character(len=512), intent(inout) :: errmsg
// CHECK-NEXT:      integer, intent(inout) :: errflg
// CHECK-NEXT:      type(ccpp_constituent_properties_t), allocatable :: dyn_const(:)
// CHECK-NEXT:      type(ccpp_constituent_properties_t), allocatable :: dyn_const_ice(:)
// CHECK-NEXT:      integer :: ccpp_num_dyn_consts
// CHECK-NEXT:      integer :: ccpp_dyn_const_index
// CHECK:           errflg = 0
// CHECK-NEXT:      if (trim(suite_name) .eq. 'cld_suite') then
// CHECK-NEXT:        call cld_suite_suite_register(dyn_const=dyn_const, dyn_const_ice=dyn_const_ice,             &
// CHECK-NEXT:          errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:        if (errflg /= 0) then
// CHECK-NEXT:          return
// CHECK-NEXT:        end if
// CHECK-NEXT:        if (allocated(cld_suite_dynamic_constituents)) deallocate(cld_suite_dynamic_constituents)
// CHECK-NEXT:        allocate(cld_suite_dynamic_constituents(0+size(dyn_const)+size(dyn_const_ice)))
// CHECK-NEXT:        ccpp_num_dyn_consts = 0
// CHECK-NEXT:        do ccpp_dyn_const_index = 1, size(dyn_const)
// CHECK-NEXT:          cld_suite_dynamic_constituents(ccpp_num_dyn_consts + ccpp_dyn_const_index) = dyn_const(ccpp_dyn_const_index)
// CHECK-NEXT:        end do
// CHECK-NEXT:        ccpp_num_dyn_consts = ccpp_num_dyn_consts + size(dyn_const)
// CHECK-NEXT:        deallocate(dyn_const)
// CHECK-NEXT:        do ccpp_dyn_const_index = 1, size(dyn_const_ice)
// CHECK-NEXT:          cld_suite_dynamic_constituents(ccpp_num_dyn_consts + ccpp_dyn_const_index) = dyn_const_ice(ccpp_dyn_const_index)
// CHECK-NEXT:        end do
// CHECK-NEXT:        ccpp_num_dyn_consts = ccpp_num_dyn_consts + size(dyn_const_ice)
// CHECK-NEXT:        deallocate(dyn_const_ice)
// CHECK-NEXT:      else
// CHECK-NEXT:        write(errmsg, '(3a)') "No suite named ", trim(suite_name), "found"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine Cld_ccpp_physics_register
// CHECK-LABEL:   subroutine Cld_ccpp_physics_initialize(suite_name, errmsg, errflg)
// CHECK:           character(len=*), intent(in) :: suite_name
// CHECK-NEXT:      character(len=512), intent(inout) :: errmsg
// CHECK-NEXT:      integer, intent(inout) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (trim(suite_name) .eq. 'cld_suite') then
// CHECK-NEXT:        call cld_suite_suite_initialize(cld_liq_array=Cld_constituents_obj%vars_layer(:, :,         &
// CHECK-NEXT:          Cld_model_const_indices(2)), cld_ice_array=Cld_constituents_obj%vars_layer(:, :,          &
// CHECK-NEXT:          Cld_model_const_indices(1)), errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      else
// CHECK-NEXT:        write(errmsg, '(3a)') "No suite named ", trim(suite_name), "found"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine Cld_ccpp_physics_initialize
// CHECK-LABEL:   subroutine Cld_ccpp_physics_finalize(suite_name, errmsg, errflg)
// CHECK:           character(len=*), intent(in) :: suite_name
// CHECK-NEXT:      character(len=512), intent(inout) :: errmsg
// CHECK-NEXT:      integer, intent(inout) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (trim(suite_name) .eq. 'cld_suite') then
// CHECK-NEXT:        call cld_suite_suite_finalize(errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      else
// CHECK-NEXT:        write(errmsg, '(3a)') "No suite named ", trim(suite_name), "found"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine Cld_ccpp_physics_finalize
// CHECK-LABEL:   subroutine Cld_ccpp_physics_timestep_initial(suite_name, errmsg, errflg)
// CHECK:           character(len=*), intent(in) :: suite_name
// CHECK-NEXT:      character(len=512), intent(inout) :: errmsg
// CHECK-NEXT:      integer, intent(inout) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (trim(suite_name) .eq. 'cld_suite') then
// CHECK-NEXT:        call cld_suite_suite_timestep_initial(errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      else
// CHECK-NEXT:        write(errmsg, '(3a)') "No suite named ", trim(suite_name), "found"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine Cld_ccpp_physics_timestep_initial
// CHECK-LABEL:   subroutine Cld_ccpp_physics_timestep_final(suite_name, errmsg, errflg)
// CHECK:           character(len=*), intent(in) :: suite_name
// CHECK-NEXT:      character(len=512), intent(inout) :: errmsg
// CHECK-NEXT:      integer, intent(inout) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (trim(suite_name) .eq. 'cld_suite') then
// CHECK-NEXT:        call cld_suite_suite_timestep_final(errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      else
// CHECK-NEXT:        write(errmsg, '(3a)') "No suite named ", trim(suite_name), "found"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine Cld_ccpp_physics_timestep_final
// CHECK-LABEL:   subroutine Cld_ccpp_physics_run(suite_name, suite_part, col_start, col_end, errmsg, errflg)
// CHECK:           character(len=*), intent(in) :: suite_name
// CHECK-NEXT:      character(len=*), intent(in) :: suite_part
// CHECK-NEXT:      integer, intent(in) :: col_start
// CHECK-NEXT:      integer, intent(in) :: col_end
// CHECK-NEXT:      character(len=512), intent(inout) :: errmsg
// CHECK-NEXT:      integer, intent(inout) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (trim(suite_name) .eq. 'cld_suite') then
// CHECK-NEXT:        if (trim(suite_part) .eq. 'physics') then
// CHECK-NEXT:          call cld_suite_suite_physics(col_start=col_start, col_end=col_end,                        &
// CHECK-NEXT:            cld_liq_tend=Cld_constituents_obj%vars_layer_tend(col_start:col_end, 1:pver,            &
// CHECK-NEXT:            Cld_model_const_indices(2)),                                                            &
// CHECK-NEXT:            const_tend=Cld_constituents_obj%vars_layer_tend(col_start:col_end, 1:pver,              &
// CHECK-NEXT:            1:Cld_constituents_obj%num_layer_vars),                                                 &
// CHECK-NEXT:            const=Cld_constituents_obj%vars_layer(col_start:col_end, 1:pver,                        &
// CHECK-NEXT:            1:Cld_constituents_obj%num_layer_vars),                                                 &
// CHECK-NEXT:            cld_ice_array=Cld_constituents_obj%vars_layer(col_start:col_end, 1:pver,                &
// CHECK-NEXT:            Cld_model_const_indices(1)), errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:        else
// CHECK-NEXT:          write(errmsg, '(3a)') "No suite part named ", trim(suite_part), " found in suite cld_suite"
// CHECK-NEXT:          errflg = 1
// CHECK-NEXT:        end if
// CHECK-NEXT:      else
// CHECK-NEXT:        write(errmsg, '(3a)') "No suite named ", trim(suite_name), "found"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine Cld_ccpp_physics_run
// CHECK-LABEL:   subroutine ccpp_physics_suite_list(suites)
// CHECK:           character(len=*), allocatable, intent(out) :: suites(:)
// CHECK:           allocate(suites(1))
// CHECK-NEXT:      suites(1) = str_cld_suite
// CHECK-NEXT:    end subroutine ccpp_physics_suite_list
// CHECK-LABEL:   subroutine ccpp_physics_suite_part_list(suite_name, part_list, errmsg, errflg)
// CHECK:           character(len=*), intent(in) :: suite_name
// CHECK-NEXT:      character(len=*), allocatable, intent(out) :: part_list(:)
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (trim(suite_name) .eq. 'cld_suite') then
// CHECK-NEXT:        allocate(part_list(1))
// CHECK-NEXT:        part_list(1) = str_physics
// CHECK-NEXT:      else
// CHECK-NEXT:        write(errmsg, '(3a)') "No suite named ", trim(suite_name), " found"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine ccpp_physics_suite_part_list
// CHECK-LABEL:   subroutine ccpp_physics_suite_variables(suite_name, variable_list, errmsg, errflg, input_vars,  &
// CHECK:           output_vars, struct_elements)
// CHECK-NEXT:      character(len=*), intent(in) :: suite_name
// CHECK-NEXT:      character(len=*), allocatable, intent(out) :: variable_list(:)
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK-NEXT:      logical, optional, intent(in) :: input_vars
// CHECK-NEXT:      logical, optional, intent(in) :: output_vars
// CHECK-NEXT:      logical, optional, intent(in) :: struct_elements
// CHECK-NEXT:      logical :: use_inputs, use_outputs
// CHECK-NEXT:      integer :: index
// CHECK:           errflg = 0
// CHECK-NEXT:      errmsg = ''
// CHECK-NEXT:      use_inputs = .true.
// CHECK-NEXT:      if (present(input_vars)) use_inputs = input_vars
// CHECK-NEXT:      use_outputs = .true.
// CHECK-NEXT:      if (present(output_vars)) use_outputs = output_vars
// CHECK-NEXT:      if (trim(suite_name) == 'cld_suite') then
// CHECK-NEXT:        if (use_inputs .and. use_outputs) then
// CHECK-NEXT:          allocate(variable_list(18))
// CHECK-NEXT:        else if (use_inputs) then
// CHECK-NEXT:          allocate(variable_list(12))
// CHECK-NEXT:        else if (use_outputs) then
// CHECK-NEXT:          allocate(variable_list(13))
// CHECK-NEXT:        else
// CHECK-NEXT:          allocate(variable_list(0))
// CHECK-NEXT:        end if
// CHECK-NEXT:        index = 0
// CHECK-NEXT:        if (use_inputs .or. use_outputs) then
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'ccpp_constituent_tendencies'
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'ccpp_constituents'
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'cloud_ice_dry_mixing_ratio'
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'cloud_liquid_dry_mixing_ratio'
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'temperature'
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'tendency_of_cloud_liquid_dry_mixing_ratio'
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'water_vapor_specific_humidity'
// CHECK-NEXT:        end if
// CHECK-NEXT:        if (use_inputs) then
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'banana_array_dim'
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'number_of_ccpp_constituents'
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'surface_air_pressure'
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'time_step_for_physics'
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'water_temperature_at_freezing'
// CHECK-NEXT:        end if
// CHECK-NEXT:        if (use_outputs) then
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'ccpp_error_code'
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'ccpp_error_message'
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'dynamic_constituents_for_cld_ice'
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'dynamic_constituents_for_cld_liq'
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'test_banana_constituent_index'
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'test_banana_constituent_indices'
// CHECK-NEXT:        end if
// CHECK-NEXT:      else
// CHECK-NEXT:        write(errmsg, '(3a)') 'No suite named ', trim(suite_name), ' found'
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine ccpp_physics_suite_variables
// CHECK-LABEL:   subroutine Cld_ccpp_register_constituents(host_constituents, errflg, errmsg)
// CHECK:           ! Create constituent object for the suites
// CHECK-NEXT:      type(ccpp_constituent_properties_t), target, intent(in) :: host_constituents(:)
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK-NEXT:      integer :: num_suite_consts
// CHECK-NEXT:      integer :: num_consts
// CHECK-NEXT:      integer :: index
// CHECK-NEXT:      integer :: field_ind
// CHECK-NEXT:      type(ccpp_constituent_properties_t), pointer :: const_prop => NULL()
// CHECK:           errflg = 0
// CHECK-NEXT:      errmsg = ''
// CHECK-NEXT:      num_consts = size(host_constituents, 1)
// CHECK-NEXT:      ! Number of suite constituents for cld_suite
// CHECK-NEXT:      num_suite_consts = cld_suite_constituents_num_consts(errflg=errflg, errmsg=errmsg)
// CHECK-NEXT:      if (errflg /= 0) then
// CHECK-NEXT:        return
// CHECK-NEXT:      end if
// CHECK-NEXT:      num_consts = num_consts + num_suite_consts
// CHECK-NEXT:      if (allocated(cld_suite_dynamic_constituents)) then
// CHECK-NEXT:        num_consts = num_consts + size(cld_suite_dynamic_constituents, 1)
// CHECK-NEXT:      end if
// CHECK-NEXT:      ! Initialize constituent data and field object
// CHECK-NEXT:      call Cld_constituents_obj%initialize_table(num_consts)
// CHECK-NEXT:      ! Add host model constituent metadata
// CHECK-NEXT:      do index = 1, size(host_constituents, 1)
// CHECK-NEXT:        const_prop => host_constituents(index)
// CHECK-NEXT:        call Cld_constituents_obj%new_field(const_prop, errcode=errflg, errmsg=errmsg)
// CHECK-NEXT:        nullify(const_prop)
// CHECK-NEXT:        if (errflg /= 0) then
// CHECK-NEXT:          return
// CHECK-NEXT:        end if
// CHECK-NEXT:      end do
// CHECK-NEXT:      ! Add the constituents that schemes of cld_suite make at run time
// CHECK-NEXT:      if (allocated(cld_suite_dynamic_constituents)) then
// CHECK-NEXT:        do index = 1, size(cld_suite_dynamic_constituents, 1)
// CHECK-NEXT:          const_prop => cld_suite_dynamic_constituents(index)
// CHECK-NEXT:          call Cld_constituents_obj%new_field(const_prop, errcode=errflg, errmsg=errmsg)
// CHECK-NEXT:          nullify(const_prop)
// CHECK-NEXT:          if (errflg /= 0) then
// CHECK-NEXT:            return
// CHECK-NEXT:          end if
// CHECK-NEXT:        end do
// CHECK-NEXT:      end if
// CHECK-NEXT:      ! Add cld_suite constituent metadata
// CHECK-NEXT:      num_suite_consts = cld_suite_constituents_num_consts(errflg=errflg, errmsg=errmsg)
// CHECK-NEXT:      if (errflg /= 0) then
// CHECK-NEXT:        return
// CHECK-NEXT:      end if
// CHECK-NEXT:      do index = 1, num_suite_consts
// CHECK-NEXT:        allocate(const_prop, stat=errflg)
// CHECK-NEXT:        if (errflg /= 0) then
// CHECK-NEXT:          errmsg = "ERROR allocating const_prop"
// CHECK-NEXT:          return
// CHECK-NEXT:        end if
// CHECK-NEXT:        call cld_suite_constituents_copy_const(index, const_prop, errflg=errflg, errmsg=errmsg)
// CHECK-NEXT:        if (errflg /= 0) then
// CHECK-NEXT:          return
// CHECK-NEXT:        end if
// CHECK-NEXT:        call Cld_constituents_obj%new_field(const_prop, errcode=errflg, errmsg=errmsg)
// CHECK-NEXT:        nullify(const_prop)
// CHECK-NEXT:        if (errflg /= 0) then
// CHECK-NEXT:          return
// CHECK-NEXT:        end if
// CHECK-NEXT:      end do
// CHECK-NEXT:      call Cld_constituents_obj%lock_table(errcode=errflg, errmsg=errmsg)
// CHECK-NEXT:      if (errflg /= 0) then
// CHECK-NEXT:        return
// CHECK-NEXT:      end if
// CHECK-NEXT:      ! Set the index for each active constituent
// CHECK-NEXT:      do index = 1, size(Cld_model_const_indices)
// CHECK-NEXT:        call Cld_constituents_obj%const_index(field_ind, Cld_model_const_stdnames(index),           &
// CHECK-NEXT:      errcode=errflg, errmsg=errmsg)
// CHECK-NEXT:        if (errflg /= 0) then
// CHECK-NEXT:          return
// CHECK-NEXT:        end if
// CHECK-NEXT:        if (field_ind > 0) then
// CHECK-NEXT:          Cld_model_const_indices(index) = field_ind
// CHECK-NEXT:        else
// CHECK-NEXT:          errflg = 1
// CHECK-NEXT:          errmsg = 'No field index for '//trim(Cld_model_const_stdnames(index))
// CHECK-NEXT:          return
// CHECK-NEXT:        end if
// CHECK-NEXT:      end do
// CHECK-NEXT:    end subroutine Cld_ccpp_register_constituents
// CHECK-LABEL:   subroutine Cld_ccpp_initialize_constituents(ncols, num_layers, errflg, errmsg)
// CHECK:           ! Initialize constituent data
// CHECK-NEXT:      use ccpp_scheme_utils, only: ccpp_initialize_constituent_ptr
// CHECK-NEXT:      integer, intent(in) :: ncols
// CHECK-NEXT:      integer, intent(in) :: num_layers
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK-NEXT:      call Cld_constituents_obj%lock_data(ncols, num_layers, errcode=errflg, errmsg=errmsg)
// CHECK-NEXT:      call ccpp_initialize_constituent_ptr(Cld_constituents_obj)
// CHECK-NEXT:    end subroutine Cld_ccpp_initialize_constituents
// CHECK-LABEL:   subroutine Cld_ccpp_number_constituents(num_flds, advected, errflg, errmsg)
// CHECK:           ! Return the number of constituent fields for this run
// CHECK-NEXT:      integer, intent(out) :: num_flds
// CHECK-NEXT:      logical, optional, intent(in) :: advected
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK-NEXT:      call Cld_constituents_obj%num_constituents(num_flds, advected=advected, errcode=errflg,       &
// CHECK-NEXT:      errmsg=errmsg)
// CHECK-NEXT:    end subroutine Cld_ccpp_number_constituents
// CHECK-LABEL:   subroutine Cld_ccpp_is_scheme_constituent(var_name, constituent_exists, errflg, errmsg)
// CHECK:           ! Return constituent_exists = true iff var_name is in Cld_model_const_stdnames
// CHECK-NEXT:      character(len=*), intent(in) :: var_name
// CHECK-NEXT:      logical, intent(out) :: constituent_exists
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK-NEXT:      errflg = 0
// CHECK-NEXT:      errmsg = ''
// CHECK-NEXT:      constituent_exists = .false.
// CHECK-NEXT:      if (any(Cld_model_const_stdnames == var_name)) then
// CHECK-NEXT:        constituent_exists = .true.
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine Cld_ccpp_is_scheme_constituent
// CHECK-LABEL:   subroutine Cld_ccpp_gather_constituents(const_array, errflg, errmsg)
// CHECK:           ! Copy constituent field info into <const_array>
// CHECK-NEXT:      real(kind_phys), intent(out) :: const_array(:,:,:)
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK-NEXT:      call Cld_constituents_obj%copy_in(const_array, errcode=errflg, errmsg=errmsg)
// CHECK-NEXT:    end subroutine Cld_ccpp_gather_constituents
// CHECK-LABEL:   subroutine Cld_ccpp_update_constituents(const_array, errflg, errmsg)
// CHECK:           ! Update constituent field info from <const_array>
// CHECK-NEXT:      real(kind_phys), intent(in) :: const_array(:,:,:)
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK-NEXT:      call Cld_constituents_obj%copy_out(const_array, errcode=errflg, errmsg=errmsg)
// CHECK-NEXT:    end subroutine Cld_ccpp_update_constituents
// CHECK-LABEL:   subroutine Cld_ccpp_deallocate_dynamic_constituents()
// CHECK:           ! Deallocate the dynamic constituent arrays and reset the object
// CHECK-NEXT:      if (allocated(cld_suite_dynamic_constituents)) then
// CHECK-NEXT:        deallocate(cld_suite_dynamic_constituents)
// CHECK-NEXT:      end if
// CHECK-NEXT:      call Cld_constituents_obj%reset()
// CHECK-NEXT:    end subroutine Cld_ccpp_deallocate_dynamic_constituents
// CHECK:         function Cld_constituents_array() result(const_ptr)
// CHECK-NEXT:      ! Return pointer to constituent array
// CHECK-NEXT:      real(kind_phys), pointer :: const_ptr(:,:,:)
// CHECK-NEXT:      const_ptr => Cld_constituents_obj%field_data_ptr()
// CHECK-NEXT:    end function Cld_constituents_array
// CHECK:         function Cld_advected_constituents_array() result(const_ptr)
// CHECK-NEXT:      ! Return pointer to advected constituent array
// CHECK-NEXT:      real(kind_phys), pointer :: const_ptr(:,:,:)
// CHECK-NEXT:      const_ptr => Cld_constituents_obj%advected_constituents_ptr()
// CHECK-NEXT:    end function Cld_advected_constituents_array
// CHECK:         function Cld_model_const_properties() result(const_ptr)
// CHECK-NEXT:      use ccpp_constituent_prop_mod, only: ccpp_constituent_prop_ptr_t
// CHECK-NEXT:      ! Return pointer to array of constituent properties
// CHECK-NEXT:      type(ccpp_constituent_prop_ptr_t), pointer :: const_ptr(:)
// CHECK-NEXT:      const_ptr => Cld_constituents_obj%constituent_props_ptr()
// CHECK-NEXT:    end function Cld_model_const_properties
// CHECK-LABEL:   subroutine Cld_const_get_index(stdname, const_index, errflg, errmsg)
// CHECK:           ! Set <const_index> to the constituent array index for <stdname>
// CHECK-NEXT:      ! If <stdname> is not found, set <const_index> to -1 and set an error
// CHECK-NEXT:      character(len=*), intent(in) :: stdname
// CHECK-NEXT:      integer, intent(out) :: const_index
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK-NEXT:      call Cld_constituents_obj%const_index(const_index, stdname, errcode=errflg, errmsg=errmsg)
// CHECK-NEXT:    end subroutine Cld_const_get_index
// CHECK-NEXT:  end module cld_ccpp_cap
// CHECK:       // -----
// CHECK-LABEL: // FILE: ccpp_kinds.F90
// CHECK-LABEL: module ccpp_kinds
// CHECK:         use ISO_FORTRAN_ENV, only: kind_phys => REAL64
// CHECK:         implicit none
// CHECK-NEXT:    private
// CHECK:         public :: kind_phys
// CHECK-NEXT:  end module ccpp_kinds

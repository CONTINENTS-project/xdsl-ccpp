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
// CHECK:         implicit none
// CHECK-NEXT:    private
// CHECK:         character(len=16) :: ccpp_suite_state = 'uninitialized'
// CHECK-NEXT:    character(len=16), parameter :: const_in_time_step = 'in_time_step'
// CHECK-NEXT:    character(len=16), parameter :: const_initialized = 'initialized'
// CHECK-NEXT:    character(len=16), parameter :: const_uninitialized = 'uninitialized'
// CHECK-NEXT:    public :: cld_suite_suite_initialize
// CHECK-NEXT:    public :: cld_suite_suite_finalize
// CHECK-NEXT:    public :: cld_suite_suite_physics
// CHECK-NEXT:    public :: cld_suite_suite_timestep_initial
// CHECK-NEXT:    public :: cld_suite_suite_timestep_final
// CHECK:       CONTAINS
// CHECK-LABEL:   subroutine cld_suite_suite_initialize(const_std_name, num_consts, test_stdname_array,           &
// CHECK:           const_inds, tfreeze, cld_liq_array, cld_ice_array, const_index, errmsg, errflg, tcld)
// CHECK-NEXT:      character(len=*), intent(in) :: const_std_name
// CHECK-NEXT:      integer, intent(in) :: num_consts
// CHECK-NEXT:      character(len=*), intent(in) :: test_stdname_array
// CHECK-NEXT:      integer, intent(inout) :: const_inds(:)
// CHECK-NEXT:      real(kind=kind_phys), intent(in) :: tfreeze
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: cld_liq_array(:, :)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: cld_ice_array(:, :)
// CHECK-NEXT:      integer, intent(out) :: const_index
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK-NEXT:      real(kind=kind_phys), intent(out) :: tcld
// CHECK:           errflg = 0
// CHECK-NEXT:      if (.NOT. (const_uninitialized .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in cld_suite_initialize"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call const_indices_init(const_std_name, num_consts, test_stdname_array, const_index,        &
// CHECK-NEXT:          const_inds, errmsg, errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call cld_liq_init(tfreeze, cld_liq_array, tcld, errmsg, errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call cld_ice_init(tfreeze, cld_ice_array, cld_ice_array, errmsg, errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      ccpp_suite_state = const_initialized
// CHECK-NEXT:    end subroutine cld_suite_suite_initialize
// CHECK-LABEL:   subroutine cld_suite_suite_finalize(errflg, errmsg)
// CHECK:           integer, intent(out) :: errflg
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (.NOT. (const_initialized .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in cld_suite_finalize"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      ccpp_suite_state = const_uninitialized
// CHECK-NEXT:    end subroutine cld_suite_suite_finalize
// CHECK-LABEL:   subroutine cld_suite_suite_physics(const_std_name, num_consts, test_stdname_array, const_inds,  &
// CHECK:           col_start, col_end, timestep, tcld, temp, qv, ps, cld_liq_tend, const_tend, const,            &
// CHECK-NEXT:      cld_ice_array, const_index, errmsg, errflg, errcode)
// CHECK-NEXT:      character(len=*), intent(in) :: const_std_name
// CHECK-NEXT:      integer, intent(in) :: num_consts
// CHECK-NEXT:      character(len=*), intent(in) :: test_stdname_array
// CHECK-NEXT:      integer, intent(inout) :: const_inds(:)
// CHECK-NEXT:      integer, intent(in) :: col_start
// CHECK-NEXT:      integer, intent(in) :: col_end
// CHECK-NEXT:      real(kind=kind_phys), intent(in) :: timestep
// CHECK-NEXT:      real(kind=kind_phys), intent(in) :: tcld
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: temp(:, :)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: qv(:, :)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: ps(:)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: cld_liq_tend(:, :)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: const_tend(:, :, :)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: const(:, :, :)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: cld_ice_array(:, :)
// CHECK-NEXT:      integer, intent(out) :: const_index
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK-NEXT:      integer, intent(out) :: errcode
// CHECK-NEXT:      integer :: ncol
// CHECK:           errflg = 0
// CHECK-NEXT:      ncol = col_end - col_start + 1
// CHECK-NEXT:      if (.NOT. (const_in_time_step .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in cld_suite_physics"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call const_indices_run(const_std_name, num_consts, test_stdname_array, const_index,         &
// CHECK-NEXT:          const_inds, errmsg, errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call cld_liq_run(ncol, timestep, tcld, temp, qv, ps, cld_liq_tend, temp, qv, cld_liq_tend,  &
// CHECK-NEXT:          errmsg, errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call apply_constituent_tendencies_run(const_tend, const, const_tend, const, errcode, errmsg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call cld_ice_run(ncol, timestep, temp, qv, ps, cld_ice_array, temp, qv, cld_ice_array,      &
// CHECK-NEXT:          errmsg, errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine cld_suite_suite_physics
// CHECK-LABEL:   subroutine cld_suite_suite_timestep_initial(errflg, errmsg)
// CHECK:           integer, intent(out) :: errflg
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (.NOT. (const_initialized .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in cld_suite_timestep_initial"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      ccpp_suite_state = const_in_time_step
// CHECK-NEXT:    end subroutine cld_suite_suite_timestep_initial
// CHECK-LABEL:   subroutine cld_suite_suite_timestep_final(errflg, errmsg)
// CHECK:           integer, intent(out) :: errflg
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
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
// CHECK-NEXT:    use cld_suite_cap, only: cld_suite_suite_finalize
// CHECK-NEXT:    use cld_suite_cap, only: cld_suite_suite_initialize
// CHECK-NEXT:    use cld_suite_cap, only: cld_suite_suite_physics
// CHECK-NEXT:    use cld_suite_cap, only: cld_suite_suite_timestep_final
// CHECK-NEXT:    use cld_suite_cap, only: cld_suite_suite_timestep_initial
// CHECK-NEXT:    use test_host_data, only: const_inds
// CHECK-NEXT:    use test_host_data, only: const_std_name
// CHECK-NEXT:    use test_host_data, only: num_consts
// CHECK-NEXT:    use test_host_data, only: std_name_array
// CHECK-NEXT:    use test_host_mod, only: dt
// CHECK:         implicit none
// CHECK-NEXT:    private
// CHECK:         character(len=9), parameter :: str_cld_suite = 'cld_suite'
// CHECK-NEXT:    character(len=7), parameter :: str_physics = 'physics'
// CHECK-NEXT:    public :: Cld_ccpp_physics_initialize
// CHECK-NEXT:    public :: Cld_ccpp_physics_finalize
// CHECK-NEXT:    public :: Cld_ccpp_physics_timestep_initial
// CHECK-NEXT:    public :: Cld_ccpp_physics_timestep_final
// CHECK-NEXT:    public :: Cld_ccpp_physics_run
// CHECK-NEXT:    public :: ccpp_physics_suite_list
// CHECK-NEXT:    public :: ccpp_physics_suite_part_list
// CHECK:       CONTAINS
// CHECK-LABEL:   subroutine Cld_ccpp_physics_initialize(suite_name, errmsg, errflg)
// CHECK:           character(len=*), intent(in) :: suite_name
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK-NEXT:      real(kind=kind_phys) :: _tmp_0
// CHECK-NEXT:      real(kind=kind_phys) :: _tmp_1
// CHECK:           errflg = 0
// CHECK-NEXT:      if (trim(suite_name) .eq. 'cld_suite') then
// CHECK-NEXT:        call cld_suite_suite_initialize(errflg, errflg, errmsg, errflg, _tmp_0, _tmp_1)
// CHECK-NEXT:      else
// CHECK-NEXT:        write(errmsg, '(3a)') "No suite named ", trim(suite_name), "found"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine Cld_ccpp_physics_initialize
// CHECK-LABEL:   subroutine Cld_ccpp_physics_finalize(suite_name, errmsg, errflg)
// CHECK:           character(len=*), intent(in) :: suite_name
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (trim(suite_name) .eq. 'cld_suite') then
// CHECK-NEXT:        call cld_suite_suite_finalize()
// CHECK-NEXT:      else
// CHECK-NEXT:        write(errmsg, '(3a)') "No suite named ", trim(suite_name), "found"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine Cld_ccpp_physics_finalize
// CHECK-LABEL:   subroutine Cld_ccpp_physics_timestep_initial(suite_name, errmsg, errflg)
// CHECK:           character(len=*), intent(in) :: suite_name
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (trim(suite_name) .eq. 'cld_suite') then
// CHECK-NEXT:        call cld_suite_suite_timestep_initial(errflg, errmsg)
// CHECK-NEXT:      else
// CHECK-NEXT:        write(errmsg, '(3a)') "No suite named ", trim(suite_name), "found"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine Cld_ccpp_physics_timestep_initial
// CHECK-LABEL:   subroutine Cld_ccpp_physics_timestep_final(suite_name, errmsg, errflg)
// CHECK:           character(len=*), intent(in) :: suite_name
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (trim(suite_name) .eq. 'cld_suite') then
// CHECK-NEXT:        call cld_suite_suite_timestep_final(errflg, errmsg)
// CHECK-NEXT:      else
// CHECK-NEXT:        write(errmsg, '(3a)') "No suite named ", trim(suite_name), "found"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine Cld_ccpp_physics_timestep_final
// CHECK-LABEL:   subroutine Cld_ccpp_physics_run(suite_name, suite_part, col_start, col_end, tcld, temp, qv, ps, &
// CHECK:           cld_liq_tend, const_tend, const, cld_ice_array, errmsg, errflg)
// CHECK-NEXT:      character(len=*), intent(in) :: suite_name
// CHECK-NEXT:      character(len=*), intent(in) :: suite_part
// CHECK-NEXT:      integer, intent(in) :: col_start
// CHECK-NEXT:      integer, intent(in) :: col_end
// CHECK-NEXT:      real(kind=kind_phys), intent(in) :: tcld
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: temp(:, :)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: qv(:, :)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: ps(:)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: cld_liq_tend(:, :)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: const_tend(:, :, :)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: const(:, :, :)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: cld_ice_array(:, :)
// CHECK-NEXT:      character(len=512), intent(inout) :: errmsg
// CHECK-NEXT:      integer, intent(inout) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (trim(suite_name) .eq. 'cld_suite') then
// CHECK-NEXT:        if (trim(suite_part) .eq. 'physics') then
// CHECK-NEXT:          call cld_suite_suite_physics(const_std_name, num_consts, std_name_array, const_inds,      &
// CHECK-NEXT:            col_start, col_end, dt, tcld, temp, qv, ps, cld_liq_tend, const_tend, const,            &
// CHECK-NEXT:            cld_ice_array, errflg, errmsg, errflg, errflg)
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
// CHECK-NEXT:  end module cld_ccpp_cap
// CHECK:       // -----
// CHECK-LABEL: // FILE: ccpp_kinds.F90
// CHECK-LABEL: module ccpp_kinds
// CHECK:         use ISO_FORTRAN_ENV, only: kind_phys => REAL64
// CHECK:         implicit none
// CHECK-NEXT:    private
// CHECK:         public :: kind_phys
// CHECK-NEXT:  end module ccpp_kinds

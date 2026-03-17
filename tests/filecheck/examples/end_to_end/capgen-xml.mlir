// Test the full XML frontend → optimizer → Fortran pipeline for the capgen
// example.  Two suites (ddt_suite, temp_suite) with DDT arguments and
// optional entry points.
//
// RUN: python3 -m xdsl_ccpp.frontend.ccpp_xml --suites examples/capgen/ddt_suite.xml,examples/capgen/temp_suite.xml --scheme-files examples/capgen/make_ddt.meta,examples/capgen/environ_conditions.meta,examples/capgen/setup_coeffs.meta,examples/capgen/temp_set.meta,examples/capgen/temp_calc_adjust.meta,examples/capgen/temp_adjust.meta --host-files examples/capgen/test_host_data.meta,examples/capgen/test_host_mod.meta,examples/capgen/test_host.meta | python3 -m xdsl_ccpp.tools.ccpp_opt -p generate-meta-cap,generate-meta-kinds,generate-suite-cap,generate-ccpp-cap,generate-kinds,strip-ccpp -t ftn | python3 -m filecheck %s

// CHECK-LABEL: // FILE: temp_suite_cap.F90
// CHECK-LABEL: module temp_suite_cap
// CHECK:         use ccpp_kinds
// CHECK:         implicit none
// CHECK-NEXT:    private
// CHECK:         character(len=16) :: ccpp_suite_state = 'uninitialized'
// CHECK-NEXT:    character(len=16), parameter :: const_in_time_step = 'in_time_step'
// CHECK-NEXT:    character(len=16), parameter :: const_initialized = 'initialized'
// CHECK-NEXT:    character(len=16), parameter :: const_uninitialized = 'uninitialized'
// CHECK-NEXT:    public :: temp_suite_suite_initialize
// CHECK-NEXT:    public :: temp_suite_suite_finalize
// CHECK-NEXT:    public :: temp_suite_suite_physics
// CHECK-NEXT:    public :: temp_suite_suite_timestep_initial
// CHECK-NEXT:    public :: temp_suite_suite_timestep_final
// CHECK:       CONTAINS
// CHECK-LABEL:   subroutine temp_suite_suite_initialize(temp_inc_in, fudge, temp_inc_set, errmsg, errflg)
// CHECK:           real(kind=kind_phys), intent(in) :: temp_inc_in
// CHECK-NEXT:      real(kind=kind_phys), intent(in) :: fudge
// CHECK-NEXT:      real(kind=kind_phys), intent(out) :: temp_inc_set
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (.NOT. (const_uninitialized .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in temp_suite_initialize"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call temp_set_init(temp_inc_in, fudge, temp_inc_set, errmsg, errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call temp_calc_adjust_init(errmsg, errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call temp_adjust_init(errmsg, errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      ccpp_suite_state = const_initialized
// CHECK-NEXT:    end subroutine temp_suite_suite_initialize
// CHECK-LABEL:   subroutine temp_suite_suite_finalize(errmsg, errflg)
// CHECK:           character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (.NOT. (const_initialized .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in temp_suite_finalize"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call temp_set_finalize(errmsg, errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call temp_calc_adjust_finalize(errmsg, errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call temp_adjust_finalize(errmsg, errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      ccpp_suite_state = const_uninitialized
// CHECK-NEXT:    end subroutine temp_suite_suite_finalize
// CHECK-LABEL:   subroutine temp_suite_suite_physics(col_start, col_end, lev, timestep, temp_level, temp_diag,   &
// CHECK:           temp, ps, to_promote, promote_pcnst, slev_lbound, soil_levs, var_array, temp_calc, temp_prev, &
// CHECK-NEXT:      temp_layer, qv, errmsg, errflg)
// CHECK-NEXT:      integer, intent(in) :: col_start
// CHECK-NEXT:      integer, intent(in) :: col_end
// CHECK-NEXT:      integer, intent(in) :: lev
// CHECK-NEXT:      real(kind=kind_phys), intent(in) :: timestep
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: temp_level(:, :)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: temp_diag(:, :)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: temp(:, :)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: ps(:)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: to_promote(:, :)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: promote_pcnst(:)
// CHECK-NEXT:      integer, intent(in) :: slev_lbound
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: soil_levs(:)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: var_array(:, :, :, :)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: temp_calc(:)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: temp_prev(:)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: temp_layer(:)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: qv(:)
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK-NEXT:      integer :: ncol
// CHECK:           errflg = 0
// CHECK-NEXT:      ncol = col_end - col_start + 1
// CHECK-NEXT:      if (.NOT. (const_in_time_step .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in temp_suite_physics"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call temp_set_run(ncol, lev, timestep, temp_level, temp_diag, ps, slev_lbound, soil_levs,   &
// CHECK-NEXT:          var_array, temp_level, temp_diag, temp, to_promote, promote_pcnst, soil_levs, var_array,  &
// CHECK-NEXT:          errmsg, errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call temp_calc_adjust_run(ncol, timestep, temp_level, temp_calc, errmsg, errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call temp_adjust_run(ncol, timestep, temp_prev, temp_layer, qv, ps, to_promote,             &
// CHECK-NEXT:          promote_pcnst, temp_layer, qv, ps, errmsg, errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine temp_suite_suite_physics
// CHECK-LABEL:   subroutine temp_suite_suite_timestep_initial(errflg, errmsg)
// CHECK:           integer, intent(out) :: errflg
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (.NOT. (const_initialized .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in temp_suite_timestep_initial"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      ccpp_suite_state = const_in_time_step
// CHECK-NEXT:    end subroutine temp_suite_suite_timestep_initial
// CHECK-LABEL:   subroutine temp_suite_suite_timestep_final(errflg, errmsg)
// CHECK:           integer, intent(out) :: errflg
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (.NOT. (const_in_time_step .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in temp_suite_timestep_final"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      ccpp_suite_state = const_initialized
// CHECK-NEXT:    end subroutine temp_suite_suite_timestep_final
// CHECK-NEXT:  end module temp_suite_cap
// CHECK:       // -----
// CHECK-LABEL: // FILE: ddt_suite_cap.F90
// CHECK-LABEL: module ddt_suite_cap
// CHECK:         use ccpp_kinds
// CHECK:         implicit none
// CHECK-NEXT:    private
// CHECK:         character(len=16) :: ccpp_suite_state = 'uninitialized'
// CHECK-NEXT:    character(len=16), parameter :: const_in_time_step = 'in_time_step'
// CHECK-NEXT:    character(len=16), parameter :: const_initialized = 'initialized'
// CHECK-NEXT:    character(len=16), parameter :: const_uninitialized = 'uninitialized'
// CHECK-NEXT:    public :: ddt_suite_suite_initialize
// CHECK-NEXT:    public :: ddt_suite_suite_finalize
// CHECK-NEXT:    public :: ddt_suite_suite_physics
// CHECK-NEXT:    public :: ddt_suite_suite_timestep_initial
// CHECK-NEXT:    public :: ddt_suite_suite_timestep_final
// CHECK:       CONTAINS
// CHECK-LABEL:   subroutine ddt_suite_suite_initialize(nbox, o3, hno3, model_times, vmr, errmsg, errflg, ntimes)
// CHECK:           integer, intent(in) :: nbox
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: o3(:)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: hno3(:)
// CHECK-NEXT:      integer, intent(inout) :: model_times(:)
// CHECK-NEXT:      type(vmr_type), intent(out) :: vmr
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK-NEXT:      integer, intent(out) :: ntimes
// CHECK:           errflg = 0
// CHECK-NEXT:      if (.NOT. (const_uninitialized .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in ddt_suite_initialize"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call make_ddt_init(nbox, vmr, errmsg, errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call environ_conditions_init(nbox, o3, hno3, ntimes, model_times, errmsg, errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      ccpp_suite_state = const_initialized
// CHECK-NEXT:    end subroutine ddt_suite_suite_initialize
// CHECK-LABEL:   subroutine ddt_suite_suite_finalize(ntimes, model_times, errmsg, errflg)
// CHECK:           integer, intent(in) :: ntimes
// CHECK-NEXT:      integer, intent(inout) :: model_times(:)
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (.NOT. (const_initialized .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in ddt_suite_finalize"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call environ_conditions_finalize(ntimes, model_times, errmsg, errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      ccpp_suite_state = const_uninitialized
// CHECK-NEXT:    end subroutine ddt_suite_suite_finalize
// CHECK-LABEL:   subroutine ddt_suite_suite_physics(cols, cole, O3, HNO3, vmr, psurf, errmsg, errflg)
// CHECK:           integer, intent(in) :: cols
// CHECK-NEXT:      integer, intent(in) :: cole
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: O3(:)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: HNO3(:)
// CHECK-NEXT:      type(vmr_type), intent(inout) :: vmr
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: psurf(:)
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (.NOT. (const_in_time_step .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in ddt_suite_physics"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call make_ddt_run(cols, cole, O3, HNO3, vmr, vmr, errmsg, errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call environ_conditions_run(psurf, errmsg, errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine ddt_suite_suite_physics
// CHECK-LABEL:   subroutine ddt_suite_suite_timestep_initial(errflg, errmsg)
// CHECK:           integer, intent(out) :: errflg
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (.NOT. (const_initialized .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in ddt_suite_timestep_initial"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      ccpp_suite_state = const_in_time_step
// CHECK-NEXT:    end subroutine ddt_suite_suite_timestep_initial
// CHECK-LABEL:   subroutine ddt_suite_suite_timestep_final(errflg, errmsg)
// CHECK:           integer, intent(out) :: errflg
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (.NOT. (const_in_time_step .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in ddt_suite_timestep_final"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      ccpp_suite_state = const_initialized
// CHECK-NEXT:    end subroutine ddt_suite_suite_timestep_final
// CHECK-NEXT:  end module ddt_suite_cap
// CHECK:       // -----
// CHECK-LABEL: // FILE: ddt_ccpp_cap.F90
// CHECK-LABEL: module ddt_ccpp_cap
// CHECK:         use ccpp_kinds
// CHECK-NEXT:    use ddt_suite_cap, only: ddt_suite_suite_finalize
// CHECK-NEXT:    use ddt_suite_cap, only: ddt_suite_suite_initialize
// CHECK-NEXT:    use ddt_suite_cap, only: ddt_suite_suite_physics
// CHECK-NEXT:    use ddt_suite_cap, only: ddt_suite_suite_timestep_final
// CHECK-NEXT:    use ddt_suite_cap, only: ddt_suite_suite_timestep_initial
// CHECK-NEXT:    use temp_suite_cap, only: temp_suite_suite_finalize
// CHECK-NEXT:    use temp_suite_cap, only: temp_suite_suite_initialize
// CHECK-NEXT:    use temp_suite_cap, only: temp_suite_suite_physics
// CHECK-NEXT:    use temp_suite_cap, only: temp_suite_suite_timestep_final
// CHECK-NEXT:    use temp_suite_cap, only: temp_suite_suite_timestep_initial
// CHECK-NEXT:    use test_host_mod, only: dt
// CHECK-NEXT:    use test_host_mod, only: pver
// CHECK-NEXT:    use test_host_mod, only: pverP
// CHECK-NEXT:    use test_host_mod, only: slev_lbound
// CHECK-NEXT:    use test_host_mod, only: temp_diag
// CHECK-NEXT:    use test_host_mod, only: temp_interfaces
// CHECK-NEXT:    use test_host_mod, only: temp_midpoints
// CHECK-NEXT:    use test_host_mod, only: var_array
// CHECK:         implicit none
// CHECK-NEXT:    private
// CHECK:         character(len=9), parameter :: str_ddt_suite = 'ddt_suite'
// CHECK-NEXT:    character(len=10), parameter :: str_temp_suite = 'temp_suite'
// CHECK-NEXT:    character(len=7), parameter :: str_physics = 'physics'
// CHECK-NEXT:    public :: Ddt_ccpp_physics_initialize
// CHECK-NEXT:    public :: Ddt_ccpp_physics_finalize
// CHECK-NEXT:    public :: Ddt_ccpp_physics_timestep_initial
// CHECK-NEXT:    public :: Ddt_ccpp_physics_timestep_final
// CHECK-NEXT:    public :: Ddt_ccpp_physics_run
// CHECK-NEXT:    public :: ccpp_physics_suite_list
// CHECK-NEXT:    public :: ccpp_physics_suite_part_list
// CHECK:       CONTAINS
// CHECK-LABEL:   subroutine Ddt_ccpp_physics_initialize(suite_name, errmsg, errflg)
// CHECK:           character(len=*), intent(in) :: suite_name
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK-NEXT:      type(vmr_type) :: _tmp_0
// CHECK-NEXT:      real(kind=kind_phys) :: _tmp_1
// CHECK-NEXT:      real(kind=kind_phys) :: _tmp_2
// CHECK-NEXT:      real(kind=kind_phys) :: _tmp_3
// CHECK:           errflg = 0
// CHECK-NEXT:      if (trim(suite_name) .eq. 'ddt_suite') then
// CHECK-NEXT:        call ddt_suite_suite_initialize(_tmp_0, errmsg, errflg, _tmp_1, _tmp_2, errflg, errflg)
// CHECK-NEXT:      else
// CHECK-NEXT:        if (trim(suite_name) .eq. 'temp_suite') then
// CHECK-NEXT:          call temp_suite_suite_initialize(_tmp_3, errmsg, errflg)
// CHECK-NEXT:        else
// CHECK-NEXT:          write(errmsg, '(3a)') "No suite named ", trim(suite_name), "found"
// CHECK-NEXT:          errflg = 1
// CHECK-NEXT:        end if
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine Ddt_ccpp_physics_initialize
// CHECK-LABEL:   subroutine Ddt_ccpp_physics_finalize(suite_name, errmsg, errflg)
// CHECK:           character(len=*), intent(in) :: suite_name
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (trim(suite_name) .eq. 'ddt_suite') then
// CHECK-NEXT:        call ddt_suite_suite_finalize(errmsg, errflg)
// CHECK-NEXT:      else
// CHECK-NEXT:        if (trim(suite_name) .eq. 'temp_suite') then
// CHECK-NEXT:          call temp_suite_suite_finalize(errmsg, errflg)
// CHECK-NEXT:        else
// CHECK-NEXT:          write(errmsg, '(3a)') "No suite named ", trim(suite_name), "found"
// CHECK-NEXT:          errflg = 1
// CHECK-NEXT:        end if
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine Ddt_ccpp_physics_finalize
// CHECK-LABEL:   subroutine Ddt_ccpp_physics_timestep_initial(suite_name, errmsg, errflg)
// CHECK:           character(len=*), intent(in) :: suite_name
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (trim(suite_name) .eq. 'ddt_suite') then
// CHECK-NEXT:        call ddt_suite_suite_timestep_initial(errflg, errmsg)
// CHECK-NEXT:      else
// CHECK-NEXT:        if (trim(suite_name) .eq. 'temp_suite') then
// CHECK-NEXT:          call temp_suite_suite_timestep_initial(errflg, errmsg)
// CHECK-NEXT:        else
// CHECK-NEXT:          write(errmsg, '(3a)') "No suite named ", trim(suite_name), "found"
// CHECK-NEXT:          errflg = 1
// CHECK-NEXT:        end if
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine Ddt_ccpp_physics_timestep_initial
// CHECK-LABEL:   subroutine Ddt_ccpp_physics_timestep_final(suite_name, errmsg, errflg)
// CHECK:           character(len=*), intent(in) :: suite_name
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (trim(suite_name) .eq. 'ddt_suite') then
// CHECK-NEXT:        call ddt_suite_suite_timestep_final(errflg, errmsg)
// CHECK-NEXT:      else
// CHECK-NEXT:        if (trim(suite_name) .eq. 'temp_suite') then
// CHECK-NEXT:          call temp_suite_suite_timestep_final(errflg, errmsg)
// CHECK-NEXT:        else
// CHECK-NEXT:          write(errmsg, '(3a)') "No suite named ", trim(suite_name), "found"
// CHECK-NEXT:          errflg = 1
// CHECK-NEXT:        end if
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine Ddt_ccpp_physics_timestep_final
// CHECK-LABEL:   subroutine Ddt_ccpp_physics_run(suite_name, suite_part, cols, cole, O3, HNO3, vmr, psurf,       &
// CHECK:           col_start, col_end, ps, to_promote, promote_pcnst, soil_levs, temp_calc, temp_prev, qv,       &
// CHECK-NEXT:      errmsg, errflg)
// CHECK-NEXT:      character(len=*), intent(in) :: suite_name
// CHECK-NEXT:      character(len=*), intent(in) :: suite_part
// CHECK-NEXT:      integer, intent(in) :: cols
// CHECK-NEXT:      integer, intent(in) :: cole
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: O3(:)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: HNO3(:)
// CHECK-NEXT:      type(vmr_type), intent(in) :: vmr
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: psurf(:)
// CHECK-NEXT:      integer, intent(in) :: col_start
// CHECK-NEXT:      integer, intent(in) :: col_end
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: ps(:)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: to_promote(:, :)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: promote_pcnst(:)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: soil_levs(:)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: temp_calc(:)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: temp_prev(:)
// CHECK-NEXT:      real(kind=kind_phys), intent(inout) :: qv(:)
// CHECK-NEXT:      character(len=512), intent(inout) :: errmsg
// CHECK-NEXT:      integer, intent(inout) :: errflg
// CHECK-NEXT:      type(vmr_type) :: _tmp_0
// CHECK:           errflg = 0
// CHECK-NEXT:      if (trim(suite_name) .eq. 'ddt_suite') then
// CHECK-NEXT:        if (trim(suite_part) .eq. 'physics') then
// CHECK-NEXT:          call ddt_suite_suite_physics(cols, cole, O3, HNO3, vmr, psurf, _tmp_0, errmsg, errflg)
// CHECK-NEXT:        else
// CHECK-NEXT:          write(errmsg, '(3a)') "No suite part named ", trim(suite_part), " found in suite ddt_suite"
// CHECK-NEXT:          errflg = 1
// CHECK-NEXT:        end if
// CHECK-NEXT:      else
// CHECK-NEXT:        if (trim(suite_name) .eq. 'temp_suite') then
// CHECK-NEXT:          if (trim(suite_part) .eq. 'physics') then
// CHECK-NEXT:            call temp_suite_suite_physics(col_start, col_end, pver, dt,                             &
// CHECK-NEXT:              temp_interfaces(col_start:col_end, 1:pverP), temp_diag,                               &
// CHECK-NEXT:              temp_midpoints(col_start:col_end, 1:pver), ps, to_promote, promote_pcnst,             &
// CHECK-NEXT:              slev_lbound, soil_levs, var_array, temp_calc, temp_prev,                              &
// CHECK-NEXT:              temp_midpoints(col_start:col_end, 1:pver), qv, errmsg, errflg)
// CHECK-NEXT:          else
// CHECK-NEXT:            write(errmsg, '(3a)') "No suite part named ", trim(suite_part),                         &
// CHECK-NEXT:              " found in suite temp_suite"
// CHECK-NEXT:            errflg = 1
// CHECK-NEXT:          end if
// CHECK-NEXT:        else
// CHECK-NEXT:          write(errmsg, '(3a)') "No suite named ", trim(suite_name), "found"
// CHECK-NEXT:          errflg = 1
// CHECK-NEXT:        end if
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine Ddt_ccpp_physics_run
// CHECK-LABEL:   subroutine ccpp_physics_suite_list(suites)
// CHECK:           character(len=*), allocatable, intent(out) :: suites(:)
// CHECK:           allocate(suites(2))
// CHECK-NEXT:      suites(1) = str_ddt_suite
// CHECK-NEXT:      suites(2) = str_temp_suite
// CHECK-NEXT:    end subroutine ccpp_physics_suite_list
// CHECK-LABEL:   subroutine ccpp_physics_suite_part_list(suite_name, part_list, errmsg, errflg)
// CHECK:           character(len=*), intent(in) :: suite_name
// CHECK-NEXT:      character(len=*), allocatable, intent(out) :: part_list(:)
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (trim(suite_name) .eq. 'ddt_suite') then
// CHECK-NEXT:        allocate(part_list(1))
// CHECK-NEXT:        part_list(1) = str_physics
// CHECK-NEXT:      else
// CHECK-NEXT:        if (trim(suite_name) .eq. 'temp_suite') then
// CHECK-NEXT:          allocate(part_list(1))
// CHECK-NEXT:          part_list(1) = str_physics
// CHECK-NEXT:        else
// CHECK-NEXT:          write(errmsg, '(3a)') "No suite named ", trim(suite_name), " found"
// CHECK-NEXT:          errflg = 1
// CHECK-NEXT:        end if
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine ccpp_physics_suite_part_list
// CHECK-NEXT:  end module ddt_ccpp_cap
// CHECK:       // -----
// CHECK-LABEL: // FILE: ccpp_kinds.F90
// CHECK-LABEL: module ccpp_kinds
// CHECK:         use ISO_FORTRAN_ENV, only: kind_phys => REAL64
// CHECK:         implicit none
// CHECK-NEXT:    private
// CHECK:         public :: kind_phys
// CHECK-NEXT:  end module ccpp_kinds

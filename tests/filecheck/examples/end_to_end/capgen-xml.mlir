// Test the full XML frontend → optimizer → Fortran pipeline for the capgen
// example.  Two suites (ddt_suite, temp_suite) with DDT arguments and
// optional entry points.
//
// RUN: python3 -m xdsl_ccpp.frontend.ccpp_xml --suites examples/capgen/ddt_suite.xml,examples/capgen/temp_suite.xml --scheme-files examples/capgen/make_ddt.meta,examples/capgen/environ_conditions.meta,examples/capgen/setup_coeffs.meta,examples/capgen/temp_set.meta,examples/capgen/temp_calc_adjust.meta,examples/capgen/temp_adjust.meta --host-files examples/capgen/test_host_data.meta,examples/capgen/test_host_mod.meta,examples/capgen/test_host.meta | python3 -m xdsl_ccpp.tools.ccpp_opt -p generate-meta-cap,generate-meta-kinds,generate-suite-cap,generate-ccpp-cap,generate-kinds,strip-ccpp -t ftn | python3 -m filecheck %s

// CHECK-LABEL: // FILE: temp_suite_cap.F90
// CHECK-LABEL: module temp_suite_cap
// CHECK:         use ccpp_kinds
// CHECK-NEXT:    use setup_coeffs, only: setup_coeffs_timestep_init
// CHECK-NEXT:    use temp_adjust, only: temp_adjust_finalize
// CHECK-NEXT:    use temp_adjust, only: temp_adjust_init
// CHECK-NEXT:    use temp_adjust, only: temp_adjust_register
// CHECK-NEXT:    use temp_adjust, only: temp_adjust_run
// CHECK-NEXT:    use temp_calc_adjust, only: temp_calc_adjust_finalize
// CHECK-NEXT:    use temp_calc_adjust, only: temp_calc_adjust_init
// CHECK-NEXT:    use temp_calc_adjust, only: temp_calc_adjust_run
// CHECK-NEXT:    use temp_set, only: temp_set_finalize
// CHECK-NEXT:    use temp_set, only: temp_set_init
// CHECK-NEXT:    use temp_set, only: temp_set_run
// CHECK-NEXT:    use temp_set, only: temp_set_timestep_initialize
// CHECK-NEXT:    use test_host_mod, only: coeffs
// CHECK-NEXT:    use test_host_mod, only: config_var
// CHECK-NEXT:    use test_host_mod, only: dt
// CHECK-NEXT:    use test_host_mod, only: index_qv
// CHECK-NEXT:    use test_host_mod, only: ncols
// CHECK-NEXT:    use test_host_mod, only: pcnst
// CHECK-NEXT:    use test_host_mod, only: phys_state
// CHECK-NEXT:    use test_host_mod, only: pver
// CHECK-NEXT:    use test_host_mod, only: pverP
// CHECK-NEXT:    use test_host_mod, only: slev_lbound
// CHECK-NEXT:    use test_host_mod, only: slev_ubound
// CHECK-NEXT:    use test_host_mod, only: temp_diag
// CHECK-NEXT:    use test_host_mod, only: temp_inc
// CHECK-NEXT:    use test_host_mod, only: temp_interfaces
// CHECK-NEXT:    use test_host_mod, only: temp_midpoints
// CHECK-NEXT:    use test_host_mod, only: var_array
// CHECK:         implicit none
// CHECK-NEXT:    private
// CHECK:         character(len=16) :: ccpp_suite_state = 'uninitialized'
// CHECK-NEXT:    character(len=16), parameter :: const_in_time_step = 'in_time_step'
// CHECK-NEXT:    character(len=16), parameter :: const_initialized = 'initialized'
// CHECK-NEXT:    character(len=16), parameter :: const_uninitialized = 'uninitialized'
// CHECK-NEXT:    real(kind=kind_phys) :: fudge = 1.0_kind_phys
// CHECK-NEXT:    real(kind=kind_phys) :: temp_inc_set
// CHECK-NEXT:    real(kind=kind_phys), allocatable :: to_promote(:, :)
// CHECK-NEXT:    real(kind=kind_phys), allocatable :: promote_pcnst(:)
// CHECK-NEXT:    real(kind=kind_phys), allocatable :: temp_calc(:)
// CHECK-NEXT:    public :: temp_suite_suite_register
// CHECK-NEXT:    public :: temp_suite_suite_initialize
// CHECK-NEXT:    public :: temp_suite_suite_finalize
// CHECK-NEXT:    public :: temp_suite_suite_physics1
// CHECK-NEXT:    public :: temp_suite_suite_physics2
// CHECK-NEXT:    public :: temp_suite_suite_timestep_initial
// CHECK-NEXT:    public :: temp_suite_suite_timestep_final
// CHECK:       CONTAINS
// CHECK-LABEL:   subroutine temp_suite_suite_register(errmsg, errflg)
// CHECK:           character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (.NOT. (const_uninitialized .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in temp_suite_register"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call temp_adjust_register(config_var=config_var, errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine temp_suite_suite_register
// CHECK-LABEL:   subroutine temp_suite_suite_initialize(errmsg, errflg)
// CHECK:           character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (.NOT. (const_uninitialized .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in temp_suite_initialize"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (.not. allocated(to_promote)) then
// CHECK-NEXT:        allocate(to_promote(1:ncols, 1:pver))
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (.not. allocated(promote_pcnst)) then
// CHECK-NEXT:        allocate(promote_pcnst(1:pcnst))
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (.not. allocated(temp_calc)) then
// CHECK-NEXT:        allocate(temp_calc(1:ncols))
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call temp_set_init(temp_inc_in=temp_inc, fudge=fudge, temp_inc_set=temp_inc_set,            &
// CHECK-NEXT:          errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call temp_calc_adjust_init(errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call temp_adjust_init(errmsg=errmsg, errflg=errflg)
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
// CHECK-NEXT:        call temp_set_finalize(errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call temp_calc_adjust_finalize(errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call temp_adjust_finalize(errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (allocated(to_promote)) deallocate(to_promote)
// CHECK-NEXT:      if (allocated(promote_pcnst)) deallocate(promote_pcnst)
// CHECK-NEXT:      if (allocated(temp_calc)) deallocate(temp_calc)
// CHECK-NEXT:      ccpp_suite_state = const_uninitialized
// CHECK-NEXT:    end subroutine temp_suite_suite_finalize
// CHECK-LABEL:   subroutine temp_suite_suite_physics1(col_start, col_end, errmsg, errflg)
// CHECK:           integer, intent(in) :: col_start
// CHECK-NEXT:      integer, intent(in) :: col_end
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK-NEXT:      integer :: ccpp_ncol
// CHECK:           errflg = 0
// CHECK-NEXT:      ccpp_ncol = col_end - col_start + 1
// CHECK-NEXT:      if (.NOT. (const_in_time_step .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in temp_suite_physics1"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call temp_set_run(ncol=ccpp_ncol, lev=pver, timestep=dt,                                    &
// CHECK-NEXT:          temp_level=temp_interfaces(col_start:col_end, 1:pverP),                                   &
// CHECK-NEXT:          temp_diag=temp_diag(col_start:col_end, 1:6), ps=phys_state%ps(col_start:col_end),         &
// CHECK-NEXT:          slev_lbound=slev_lbound, soil_levs=phys_state%soil_levs,                                  &
// CHECK-NEXT:          var_array=var_array(col_start:col_end, 1:2, 1:4, 1:6),                                    &
// CHECK-NEXT:          temp=temp_midpoints(col_start:col_end, 1:pver), to_promote=to_promote(col_start:col_end,  &
// CHECK-NEXT:          1:pver), promote_pcnst=promote_pcnst, errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine temp_suite_suite_physics1
// CHECK-LABEL:   subroutine temp_suite_suite_physics2(col_start, col_end, errmsg, errflg)
// CHECK:           integer, intent(in) :: col_start
// CHECK-NEXT:      integer, intent(in) :: col_end
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK-NEXT:      integer :: ccpp_ncol
// CHECK-NEXT:      integer :: vertical_layer_index
// CHECK:           errflg = 0
// CHECK-NEXT:      ccpp_ncol = col_end - col_start + 1
// CHECK-NEXT:      if (.NOT. (const_in_time_step .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in temp_suite_physics2"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call temp_calc_adjust_run(nbox=ccpp_ncol, timestep=dt,                                      &
// CHECK-NEXT:          temp_level=temp_interfaces(col_start:col_end, 1:pverP),                                   &
// CHECK-NEXT:          temp_calc=temp_calc(col_start:col_end), errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      do vertical_layer_index = 1, pver
// CHECK-NEXT:        if (errflg .eq. 0) then
// CHECK-NEXT:          if ((index_qv > 0)) then
// CHECK-NEXT:            call temp_adjust_run(foo=ccpp_ncol, timestep=dt,                                        &
// CHECK-NEXT:              temp_prev=temp_calc(col_start:col_end), temp_layer=temp_midpoints(col_start:col_end,  &
// CHECK-NEXT:              vertical_layer_index), qv=phys_state%q(col_start:col_end, vertical_layer_index,       &
// CHECK-NEXT:              index_qv), ps=phys_state%ps(col_start:col_end),                                       &
// CHECK-NEXT:              to_promote=to_promote(col_start:col_end, vertical_layer_index),                       &
// CHECK-NEXT:              promote_pcnst=promote_pcnst, errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:          else
// CHECK-NEXT:            call temp_adjust_run(foo=ccpp_ncol, timestep=dt,                                        &
// CHECK-NEXT:              temp_prev=temp_calc(col_start:col_end), temp_layer=temp_midpoints(col_start:col_end,  &
// CHECK-NEXT:              vertical_layer_index), ps=phys_state%ps(col_start:col_end),                           &
// CHECK-NEXT:              to_promote=to_promote(col_start:col_end, vertical_layer_index),                       &
// CHECK-NEXT:              promote_pcnst=promote_pcnst, errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:          end if
// CHECK-NEXT:        end if
// CHECK-NEXT:      end do
// CHECK-NEXT:    end subroutine temp_suite_suite_physics2
// CHECK-LABEL:   subroutine temp_suite_suite_timestep_initial(errmsg, errflg)
// CHECK:           character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (.NOT. (const_initialized .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in temp_suite_timestep_initial"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call setup_coeffs_timestep_init(coeffs=coeffs, errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call temp_set_timestep_initialize(ncol=ncols, temp_inc=temp_inc_set,                        &
// CHECK-NEXT:          temp_level=temp_interfaces, errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      ccpp_suite_state = const_in_time_step
// CHECK-NEXT:    end subroutine temp_suite_suite_timestep_initial
// CHECK-LABEL:   subroutine temp_suite_suite_timestep_final(errmsg, errflg)
// CHECK:           character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
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
// CHECK-NEXT:    use environ_conditions, only: environ_conditions_finalize
// CHECK-NEXT:    use environ_conditions, only: environ_conditions_init
// CHECK-NEXT:    use environ_conditions, only: environ_conditions_run
// CHECK-NEXT:    use make_ddt, only: make_ddt_init
// CHECK-NEXT:    use make_ddt, only: make_ddt_run
// CHECK-NEXT:    use make_ddt, only: make_ddt_timestep_final
// CHECK-NEXT:    use make_ddt, only: vmr_type
// CHECK-NEXT:    use test_host_mod, only: model_times
// CHECK-NEXT:    use test_host_mod, only: ncols
// CHECK-NEXT:    use test_host_mod, only: num_model_times
// CHECK-NEXT:    use test_host_mod, only: phys_state
// CHECK:         implicit none
// CHECK-NEXT:    private
// CHECK:         character(len=16) :: ccpp_suite_state = 'uninitialized'
// CHECK-NEXT:    character(len=16), parameter :: const_in_time_step = 'in_time_step'
// CHECK-NEXT:    character(len=16), parameter :: const_initialized = 'initialized'
// CHECK-NEXT:    character(len=16), parameter :: const_uninitialized = 'uninitialized'
// CHECK-NEXT:    type(vmr_type) :: vmr
// CHECK-NEXT:    real(kind=kind_phys), allocatable :: o3(:)
// CHECK-NEXT:    real(kind=kind_phys), allocatable :: hno3(:)
// CHECK-NEXT:    public :: ddt_suite_suite_register
// CHECK-NEXT:    public :: ddt_suite_suite_initialize
// CHECK-NEXT:    public :: ddt_suite_suite_finalize
// CHECK-NEXT:    public :: ddt_suite_suite_data_prep
// CHECK-NEXT:    public :: ddt_suite_suite_timestep_initial
// CHECK-NEXT:    public :: ddt_suite_suite_timestep_final
// CHECK:       CONTAINS
// CHECK-LABEL:   subroutine ddt_suite_suite_register(errmsg, errflg)
// CHECK:           character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (.NOT. (const_uninitialized .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in ddt_suite_register"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine ddt_suite_suite_register
// CHECK-LABEL:   subroutine ddt_suite_suite_initialize(errmsg, errflg)
// CHECK:           character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (.NOT. (const_uninitialized .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in ddt_suite_initialize"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (.not. allocated(o3)) then
// CHECK-NEXT:        allocate(o3(1:ncols))
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (.not. allocated(hno3)) then
// CHECK-NEXT:        allocate(hno3(1:ncols))
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call make_ddt_init(nbox=ncols, vmr=vmr, errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call environ_conditions_init(nbox=ncols, o3=o3, hno3=hno3, ntimes=num_model_times,          &
// CHECK-NEXT:          model_times=model_times, errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      ccpp_suite_state = const_initialized
// CHECK-NEXT:    end subroutine ddt_suite_suite_initialize
// CHECK-LABEL:   subroutine ddt_suite_suite_finalize(errmsg, errflg)
// CHECK:           character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (.NOT. (const_initialized .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in ddt_suite_finalize"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call environ_conditions_finalize(ntimes=num_model_times, model_times=model_times,           &
// CHECK-NEXT:          errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (allocated(o3)) deallocate(o3)
// CHECK-NEXT:      if (allocated(hno3)) deallocate(hno3)
// CHECK-NEXT:      ccpp_suite_state = const_uninitialized
// CHECK-NEXT:    end subroutine ddt_suite_suite_finalize
// CHECK-LABEL:   subroutine ddt_suite_suite_data_prep(col_start, col_end, errmsg, errflg)
// CHECK:           integer, intent(in) :: col_start
// CHECK-NEXT:      integer, intent(in) :: col_end
// CHECK-NEXT:      character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK-NEXT:      integer :: ccpp_ncol
// CHECK:           errflg = 0
// CHECK-NEXT:      ccpp_ncol = col_end - col_start + 1
// CHECK-NEXT:      if (.NOT. (const_in_time_step .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in ddt_suite_data_prep"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call make_ddt_run(cols=col_start, cole=col_end, O3=o3(col_start:col_end),                   &
// CHECK-NEXT:          HNO3=hno3(col_start:col_end), vmr=vmr, errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call environ_conditions_run(psurf=phys_state%ps(col_start:col_end), errmsg=errmsg,          &
// CHECK-NEXT:          errflg=errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine ddt_suite_suite_data_prep
// CHECK-LABEL:   subroutine ddt_suite_suite_timestep_initial(errmsg, errflg)
// CHECK:           character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (.NOT. (const_initialized .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in ddt_suite_timestep_initial"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      ccpp_suite_state = const_in_time_step
// CHECK-NEXT:    end subroutine ddt_suite_suite_timestep_initial
// CHECK-LABEL:   subroutine ddt_suite_suite_timestep_final(errmsg, errflg)
// CHECK:           character(len=512), intent(out) :: errmsg
// CHECK-NEXT:      integer, intent(out) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (.NOT. (const_in_time_step .eq. ccpp_suite_state)) then
// CHECK-NEXT:        write(errmsg, '(3a)') "Invalid initial CCPP state, '", trim(ccpp_suite_state),              &
// CHECK-NEXT:          "' in ddt_suite_timestep_final"
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:      if (errflg .eq. 0) then
// CHECK-NEXT:        call make_ddt_timestep_final(ncols=ncols, vmr=vmr, errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      end if
// CHECK-NEXT:      ccpp_suite_state = const_initialized
// CHECK-NEXT:    end subroutine ddt_suite_suite_timestep_final
// CHECK-NEXT:  end module ddt_suite_cap
// CHECK:       // -----
// CHECK-LABEL: // FILE: ddt_ccpp_cap.F90
// CHECK-LABEL: module ddt_ccpp_cap
// CHECK:         use ccpp_kinds
// CHECK-NEXT:    use ddt_suite_cap, only: ddt_suite_suite_data_prep
// CHECK-NEXT:    use ddt_suite_cap, only: ddt_suite_suite_finalize
// CHECK-NEXT:    use ddt_suite_cap, only: ddt_suite_suite_initialize
// CHECK-NEXT:    use ddt_suite_cap, only: ddt_suite_suite_register
// CHECK-NEXT:    use ddt_suite_cap, only: ddt_suite_suite_timestep_final
// CHECK-NEXT:    use ddt_suite_cap, only: ddt_suite_suite_timestep_initial
// CHECK-NEXT:    use temp_suite_cap, only: temp_suite_suite_finalize
// CHECK-NEXT:    use temp_suite_cap, only: temp_suite_suite_initialize
// CHECK-NEXT:    use temp_suite_cap, only: temp_suite_suite_physics1
// CHECK-NEXT:    use temp_suite_cap, only: temp_suite_suite_physics2
// CHECK-NEXT:    use temp_suite_cap, only: temp_suite_suite_register
// CHECK-NEXT:    use temp_suite_cap, only: temp_suite_suite_timestep_final
// CHECK-NEXT:    use temp_suite_cap, only: temp_suite_suite_timestep_initial
// CHECK:         implicit none
// CHECK-NEXT:    private
// CHECK:         character(len=9), parameter :: str_ddt_suite = 'ddt_suite'
// CHECK-NEXT:    character(len=10), parameter :: str_temp_suite = 'temp_suite'
// CHECK-NEXT:    character(len=9), parameter :: str_data_prep = 'data_prep'
// CHECK-NEXT:    character(len=8), parameter :: str_physics1 = 'physics1'
// CHECK-NEXT:    character(len=8), parameter :: str_physics2 = 'physics2'
// CHECK-NEXT:    public :: Ddt_ccpp_physics_register
// CHECK-NEXT:    public :: Ddt_ccpp_physics_initialize
// CHECK-NEXT:    public :: Ddt_ccpp_physics_finalize
// CHECK-NEXT:    public :: Ddt_ccpp_physics_timestep_initial
// CHECK-NEXT:    public :: Ddt_ccpp_physics_timestep_final
// CHECK-NEXT:    public :: Ddt_ccpp_physics_run
// CHECK-NEXT:    public :: ccpp_physics_suite_list
// CHECK-NEXT:    public :: ccpp_physics_suite_part_list
// CHECK-NEXT:    public :: ccpp_physics_suite_variables
// CHECK:       CONTAINS
// CHECK-LABEL:   subroutine Ddt_ccpp_physics_register(suite_name, errmsg, errflg)
// CHECK:           character(len=*), intent(in) :: suite_name
// CHECK-NEXT:      character(len=512), intent(inout) :: errmsg
// CHECK-NEXT:      integer, intent(inout) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (trim(suite_name) .eq. 'ddt_suite') then
// CHECK-NEXT:        call ddt_suite_suite_register(errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      else
// CHECK-NEXT:        if (trim(suite_name) .eq. 'temp_suite') then
// CHECK-NEXT:          call temp_suite_suite_register(errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:        else
// CHECK-NEXT:          write(errmsg, '(3a)') "No suite named ", trim(suite_name), "found"
// CHECK-NEXT:          errflg = 1
// CHECK-NEXT:        end if
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine Ddt_ccpp_physics_register
// CHECK-LABEL:   subroutine Ddt_ccpp_physics_initialize(suite_name, errmsg, errflg)
// CHECK:           character(len=*), intent(in) :: suite_name
// CHECK-NEXT:      character(len=512), intent(inout) :: errmsg
// CHECK-NEXT:      integer, intent(inout) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (trim(suite_name) .eq. 'ddt_suite') then
// CHECK-NEXT:        call ddt_suite_suite_initialize(errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      else
// CHECK-NEXT:        if (trim(suite_name) .eq. 'temp_suite') then
// CHECK-NEXT:          call temp_suite_suite_initialize(errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:        else
// CHECK-NEXT:          write(errmsg, '(3a)') "No suite named ", trim(suite_name), "found"
// CHECK-NEXT:          errflg = 1
// CHECK-NEXT:        end if
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine Ddt_ccpp_physics_initialize
// CHECK-LABEL:   subroutine Ddt_ccpp_physics_finalize(suite_name, errmsg, errflg)
// CHECK:           character(len=*), intent(in) :: suite_name
// CHECK-NEXT:      character(len=512), intent(inout) :: errmsg
// CHECK-NEXT:      integer, intent(inout) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (trim(suite_name) .eq. 'ddt_suite') then
// CHECK-NEXT:        call ddt_suite_suite_finalize(errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      else
// CHECK-NEXT:        if (trim(suite_name) .eq. 'temp_suite') then
// CHECK-NEXT:          call temp_suite_suite_finalize(errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:        else
// CHECK-NEXT:          write(errmsg, '(3a)') "No suite named ", trim(suite_name), "found"
// CHECK-NEXT:          errflg = 1
// CHECK-NEXT:        end if
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine Ddt_ccpp_physics_finalize
// CHECK-LABEL:   subroutine Ddt_ccpp_physics_timestep_initial(suite_name, errmsg, errflg)
// CHECK:           character(len=*), intent(in) :: suite_name
// CHECK-NEXT:      character(len=512), intent(inout) :: errmsg
// CHECK-NEXT:      integer, intent(inout) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (trim(suite_name) .eq. 'ddt_suite') then
// CHECK-NEXT:        call ddt_suite_suite_timestep_initial(errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      else
// CHECK-NEXT:        if (trim(suite_name) .eq. 'temp_suite') then
// CHECK-NEXT:          call temp_suite_suite_timestep_initial(errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:        else
// CHECK-NEXT:          write(errmsg, '(3a)') "No suite named ", trim(suite_name), "found"
// CHECK-NEXT:          errflg = 1
// CHECK-NEXT:        end if
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine Ddt_ccpp_physics_timestep_initial
// CHECK-LABEL:   subroutine Ddt_ccpp_physics_timestep_final(suite_name, errmsg, errflg)
// CHECK:           character(len=*), intent(in) :: suite_name
// CHECK-NEXT:      character(len=512), intent(inout) :: errmsg
// CHECK-NEXT:      integer, intent(inout) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (trim(suite_name) .eq. 'ddt_suite') then
// CHECK-NEXT:        call ddt_suite_suite_timestep_final(errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:      else
// CHECK-NEXT:        if (trim(suite_name) .eq. 'temp_suite') then
// CHECK-NEXT:          call temp_suite_suite_timestep_final(errmsg=errmsg, errflg=errflg)
// CHECK-NEXT:        else
// CHECK-NEXT:          write(errmsg, '(3a)') "No suite named ", trim(suite_name), "found"
// CHECK-NEXT:          errflg = 1
// CHECK-NEXT:        end if
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine Ddt_ccpp_physics_timestep_final
// CHECK-LABEL:   subroutine Ddt_ccpp_physics_run(suite_name, suite_part, col_start, col_end, errmsg, errflg)
// CHECK:           character(len=*), intent(in) :: suite_name
// CHECK-NEXT:      character(len=*), intent(in) :: suite_part
// CHECK-NEXT:      integer, intent(in) :: col_start
// CHECK-NEXT:      integer, intent(in) :: col_end
// CHECK-NEXT:      character(len=512), intent(inout) :: errmsg
// CHECK-NEXT:      integer, intent(inout) :: errflg
// CHECK:           errflg = 0
// CHECK-NEXT:      if (trim(suite_name) .eq. 'ddt_suite') then
// CHECK-NEXT:        if (trim(suite_part) .eq. 'data_prep') then
// CHECK-NEXT:          call ddt_suite_suite_data_prep(col_start=col_start, col_end=col_end, errmsg=errmsg,       &
// CHECK-NEXT:            errflg=errflg)
// CHECK-NEXT:        else
// CHECK-NEXT:          write(errmsg, '(3a)') "No suite part named ", trim(suite_part), " found in suite ddt_suite"
// CHECK-NEXT:          errflg = 1
// CHECK-NEXT:        end if
// CHECK-NEXT:      else
// CHECK-NEXT:        if (trim(suite_name) .eq. 'temp_suite') then
// CHECK-NEXT:          if (trim(suite_part) .eq. 'physics1') then
// CHECK-NEXT:            call temp_suite_suite_physics1(col_start=col_start, col_end=col_end, errmsg=errmsg,     &
// CHECK-NEXT:              errflg=errflg)
// CHECK-NEXT:          else
// CHECK-NEXT:            if (trim(suite_part) .eq. 'physics2') then
// CHECK-NEXT:              call temp_suite_suite_physics2(col_start=col_start, col_end=col_end, errmsg=errmsg,   &
// CHECK-NEXT:                errflg=errflg)
// CHECK-NEXT:            else
// CHECK-NEXT:              write(errmsg, '(3a)') "No suite part named ", trim(suite_part),                       &
// CHECK-NEXT:                " found in suite temp_suite"
// CHECK-NEXT:              errflg = 1
// CHECK-NEXT:            end if
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
// CHECK-NEXT:        part_list(1) = str_data_prep
// CHECK-NEXT:      else
// CHECK-NEXT:        if (trim(suite_name) .eq. 'temp_suite') then
// CHECK-NEXT:          allocate(part_list(2))
// CHECK-NEXT:          part_list(1) = str_physics1
// CHECK-NEXT:          part_list(2) = str_physics2
// CHECK-NEXT:        else
// CHECK-NEXT:          write(errmsg, '(3a)') "No suite named ", trim(suite_name), " found"
// CHECK-NEXT:          errflg = 1
// CHECK-NEXT:        end if
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
// CHECK-NEXT:      if (trim(suite_name) == 'ddt_suite') then
// CHECK-NEXT:        if (use_inputs .and. use_outputs) then
// CHECK-NEXT:          allocate(variable_list(5))
// CHECK-NEXT:        else if (use_inputs) then
// CHECK-NEXT:          allocate(variable_list(3))
// CHECK-NEXT:        else if (use_outputs) then
// CHECK-NEXT:          allocate(variable_list(5))
// CHECK-NEXT:        else
// CHECK-NEXT:          allocate(variable_list(0))
// CHECK-NEXT:        end if
// CHECK-NEXT:        index = 0
// CHECK-NEXT:        if (use_inputs .or. use_outputs) then
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'model_times'
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'number_of_model_times'
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'surface_air_pressure'
// CHECK-NEXT:        end if
// CHECK-NEXT:        if (use_inputs) then
// CHECK-NEXT:        end if
// CHECK-NEXT:        if (use_outputs) then
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'ccpp_error_code'
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'ccpp_error_message'
// CHECK-NEXT:        end if
// CHECK-NEXT:      else if (trim(suite_name) == 'temp_suite') then
// CHECK-NEXT:        if (use_inputs .and. use_outputs) then
// CHECK-NEXT:          allocate(variable_list(12))
// CHECK-NEXT:        else if (use_inputs) then
// CHECK-NEXT:          allocate(variable_list(10))
// CHECK-NEXT:        else if (use_outputs) then
// CHECK-NEXT:          allocate(variable_list(10))
// CHECK-NEXT:        else
// CHECK-NEXT:          allocate(variable_list(0))
// CHECK-NEXT:        end if
// CHECK-NEXT:        index = 0
// CHECK-NEXT:        if (use_inputs .or. use_outputs) then
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'array_variable_for_testing'
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'coefficients_for_interpolation'
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'potential_temperature'
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'potential_temperature_at_interface'
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'soil_levels'
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'surface_air_pressure'
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'temperature_at_diagnostic_levels'
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'water_vapor_specific_humidity'
// CHECK-NEXT:        end if
// CHECK-NEXT:        if (use_inputs) then
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'potential_temperature_increment'
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'time_step_for_physics'
// CHECK-NEXT:        end if
// CHECK-NEXT:        if (use_outputs) then
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'ccpp_error_code'
// CHECK-NEXT:          index = index + 1
// CHECK-NEXT:          variable_list(index) = 'ccpp_error_message'
// CHECK-NEXT:        end if
// CHECK-NEXT:      else
// CHECK-NEXT:        write(errmsg, '(3a)') 'No suite named ', trim(suite_name), ' found'
// CHECK-NEXT:        errflg = 1
// CHECK-NEXT:      end if
// CHECK-NEXT:    end subroutine ccpp_physics_suite_variables
// CHECK-NEXT:  end module ddt_ccpp_cap
// CHECK:       // -----
// CHECK-LABEL: // FILE: ccpp_kinds.F90
// CHECK-LABEL: module ccpp_kinds
// CHECK:         use ISO_FORTRAN_ENV, only: kind_phys => REAL64
// CHECK:         implicit none
// CHECK-NEXT:    private
// CHECK:         public :: kind_phys
// CHECK-NEXT:  end module ccpp_kinds

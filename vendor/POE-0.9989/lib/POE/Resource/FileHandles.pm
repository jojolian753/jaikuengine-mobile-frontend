# $Id: FileHandles.pm 2087 2006-09-01 10:24:43Z bsmith $

# Manage file handles, associated descriptors, and read/write modes
# thereon.

package POE::Resource::FileHandles;

use vars qw($VERSION);
$VERSION = do {my($r)=(q$Revision: 2087 $=~/(\d+)/);sprintf"1.%04d",$r};

# These methods are folded into POE::Kernel;
package POE::Kernel;

use strict;

### Some portability things.

# Provide dummy constants so things at least compile.  These constants
# aren't used if we're RUNNING_IN_HELL, but Perl needs to see them.

BEGIN {
  if (RUNNING_IN_HELL) {
    eval '*F_GETFL = sub { 0 };';
    eval '*F_SETFL = sub { 0 };';
  }
}

### A local reference to POE::Kernel's queue.

my $kr_queue;

### Fileno structure.  This tracks the sessions that are watching a
### file, by its file number.  It used to track by file handle, but
### several handles can point to the same underlying fileno.  This is
### more unique.

my %kr_filenos;

sub FNO_MODE_RD      () { MODE_RD } # [ [ (fileno read mode structure)
# --- BEGIN SUB STRUCT 1 ---        #
sub FMO_REFCOUNT     () { 0      }  #     $fileno_total_use_count,
sub FMO_ST_ACTUAL    () { 1      }  #     $requested_file_state (see HS_PAUSED)
sub FMO_ST_REQUEST   () { 2      }  #     $actual_file_state (see HS_PAUSED)
sub FMO_EV_COUNT     () { 3      }  #     $number_of_pending_events,
sub FMO_SESSIONS     () { 4      }  #     { $session_watching_this_handle =>
                                    #       { $handle_watched_as =>
# --- BEGIN SUB STRUCT 2 ---        #
sub HSS_HANDLE       () { 0      }  #         [ $blessed_handle,
sub HSS_SESSION      () { 1      }  #           $blessed_session,
sub HSS_STATE        () { 2      }  #           $event_name,
sub HSS_ARGS         () { 3      }  #           \@callback_arguments
                                    #         ],
                                    #       },
# --- CEASE SUB STRUCT 2 ---        #     },
# --- CEASE SUB STRUCT 1 ---        #   ],
                                    #
sub FNO_MODE_WR      () { MODE_WR } #   [ (write mode structure is the same)
                                    #   ],
                                    #
sub FNO_MODE_EX      () { MODE_EX } #   [ (expedite mode struct is the same)
                                    #   ],
                                    #
sub FNO_TOT_REFCOUNT () { 3      }  #   $total_number_of_file_watchers,
                                    # ]

### These are the values for FMO_ST_ACTUAL and FMO_ST_REQUEST.

sub HS_STOPPED   () { 0x00 }   # The file has stopped generating events.
sub HS_PAUSED    () { 0x01 }   # The file temporarily stopped making events.
sub HS_RUNNING   () { 0x02 }   # The file is running and can generate events.

### Handle to session.

my %kr_ses_to_handle;

                            #    { $session =>
                            #      $handle =>
# --- BEGIN SUB STRUCT ---  #        [
sub SH_HANDLE     () {  0 } #          $blessed_file_handle,
sub SH_REFCOUNT   () {  1 } #          $total_reference_count,
sub SH_MODECOUNT  () {  2 } #          [ $read_reference_count,     (MODE_RD)
                            #            $write_reference_count,    (MODE_WR)
                            #            $expedite_reference_count, (MODE_EX)
# --- CEASE SUB STRUCT ---  #          ],
                            #        ],
                            #        ...
                            #      },
                            #    },

sub _data_handle_preload {
    $poe_kernel->[KR_FILENOS] = \%kr_filenos;
}
use POE::API::ResLoader \&_data_handle_preload;

### Begin-run initialization.

sub _data_handle_initialize {
  my ($self, $queue) = @_;
  $kr_queue = $queue;
}

### End-run leak checking.

sub _data_handle_finalize {
  my $finalized_ok = 1;

  while (my ($fd, $fd_rec) = each(%kr_filenos)) {
    my ($rd, $wr, $ex, $tot) = @$fd_rec;
    $finalized_ok = 0;

    _warn "!!! Leaked fileno: $fd (total refcnt=$tot)\n";

    _warn(
      "!!!\tRead:\n",
      "!!!\t\trefcnt  = $rd->[FMO_REFCOUNT]\n",
      "!!!\t\tev cnt  = $rd->[FMO_EV_COUNT]\n",
    );
    while (my ($ses, $ses_rec) = each(%{$rd->[FMO_SESSIONS]})) {
      _warn "!!!\t\tsession = $ses\n";
      while (my ($handle, $hnd_rec) = each(%{$ses_rec})) {
        _warn(
          "!!!\t\t\thandle  = $hnd_rec->[HSS_HANDLE]\n",
          "!!!\t\t\tsession = $hnd_rec->[HSS_SESSION]\n",
          "!!!\t\t\tevent   = $hnd_rec->[HSS_STATE]\n",
          "!!!\t\t\targs    = (@{$hnd_rec->[HSS_ARGS]})\n",
        );
      }
    }

    _warn(
      "!!!\tWrite:\n",
      "!!!\t\trefcnt  = $wr->[FMO_REFCOUNT]\n",
      "!!!\t\tev cnt  = $wr->[FMO_EV_COUNT]\n",
    );
    while (my ($ses, $ses_rec) = each(%{$wr->[FMO_SESSIONS]})) {
      _warn "!!!\t\tsession = $ses\n";
      while (my ($handle, $hnd_rec) = each(%{$ses_rec})) {
        _warn(
          "!!!\t\t\thandle  = $hnd_rec->[HSS_HANDLE]\n",
          "!!!\t\t\tsession = $hnd_rec->[HSS_SESSION]\n",
          "!!!\t\t\tevent   = $hnd_rec->[HSS_STATE]\n",
          "!!!\t\t\targs    = (@{$hnd_rec->[HSS_ARGS]})\n",
        );
      }
    }

    _warn(
      "!!!\tException:\n",
      "!!!\t\trefcnt  = $ex->[FMO_REFCOUNT]\n",
      "!!!\t\tev cnt  = $ex->[FMO_EV_COUNT]\n",
    );
    while (my ($ses, $ses_rec) = each(%{$ex->[FMO_SESSIONS]})) {
      _warn "!!!\t\tsession = $ses\n";
      while (my ($handle, $hnd_rec) = each(%{$ses_rec})) {
        _warn(
          "!!!\t\t\thandle  = $hnd_rec->[HSS_HANDLE]\n",
          "!!!\t\t\tsession = $hnd_rec->[HSS_SESSION]\n",
          "!!!\t\t\tevent   = $hnd_rec->[HSS_STATE]\n",
          "!!!\t\t\targs    = (@{$hnd_rec->[HSS_ARGS]})\n",
        );
      }
    }
  }

  while (my ($ses, $hnd_rec) = each(%kr_ses_to_handle)) {
    $finalized_ok = 0;
    _warn "!!! Leaked handle in $ses\n";
    while (my ($hnd, $rc) = each(%$hnd_rec)) {
      _warn(
        "!!!\tHandle: $hnd (tot refcnt=$rc->[SH_REFCOUNT])\n",
        "!!!\t\tRead      refcnt: $rc->[SH_MODECOUNT]->[MODE_RD]\n",
        "!!!\t\tWrite     refcnt: $rc->[SH_MODECOUNT]->[MODE_WR]\n",
        "!!!\t\tException refcnt: $rc->[SH_MODECOUNT]->[MODE_EX]\n",
      );
    }
  }

  return $finalized_ok;
}

### Ensure a handle's actual state matches its requested one.  Pause
### or resume the handle as necessary.

sub _data_handle_resume_requested_state {
  my ($self, $handle, $mode) = @_;
  my $fileno = fileno($handle);

  # Skip the rest if we aren't watching the file descriptor.  This
  # seems like a kludge: should we even be called if the descriptor
  # isn't watched?
  return unless exists $kr_filenos{$fileno};

  my $kr_fno_rec  = $kr_filenos{$fileno}->[$mode];

  if (TRACE_FILES) {
    _warn(
      "<fh> decrementing event count in mode ($mode) ",
      "for fileno (", $fileno, ") from count (",
      $kr_fno_rec->[FMO_EV_COUNT], ")"
    );
  }

  # If all events for the fileno/mode pair have been delivered, then
  # resume the filehandle's watcher.  This decrements FMO_EV_COUNT
  # because the event has just been dispatched.  This makes sense.

  unless (--$kr_fno_rec->[FMO_EV_COUNT]) {
    if ($kr_fno_rec->[FMO_ST_REQUEST] & HS_PAUSED) {
      $self->loop_pause_filehandle($handle, $mode);
      $kr_fno_rec->[FMO_ST_ACTUAL] = HS_PAUSED;
    }
    elsif ($kr_fno_rec->[FMO_ST_REQUEST] & HS_RUNNING) {
      $self->loop_resume_filehandle($handle, $mode);
      $kr_fno_rec->[FMO_ST_ACTUAL] = HS_RUNNING;
    }
    elsif (ASSERT_DATA) {
      _trap();
    }
  }
  elsif (ASSERT_DATA) {
    if ($kr_fno_rec->[FMO_EV_COUNT] < 0) {
      _trap "handle event count went below zero";
    }
  }
}

### Enqueue "select" events for a list of file descriptors in a given
### access mode.

sub _data_handle_enqueue_ready {
  my ($self, $mode, @filenos) = @_;

  foreach my $fileno (@filenos) {
    if (ASSERT_DATA) {
      _trap "internal inconsistency: undefined fileno" unless defined $fileno;
    }

    my $kr_fno_rec = $kr_filenos{$fileno}->[$mode];

    # Gather all the events to emit for this fileno/mode pair.

    my @selects = map { values %$_ } values %{ $kr_fno_rec->[FMO_SESSIONS] };

    # Emit them.

    foreach my $select (@selects) {
      $self->_data_ev_enqueue(
        $select->[HSS_SESSION], $select->[HSS_SESSION],
        $select->[HSS_STATE], ET_SELECT,
        [ $select->[HSS_HANDLE],  # EA_SEL_HANDLE
          $mode,                  # EA_SEL_MODE
          @{$select->[HSS_ARGS]}, # EA_SEL_ARGS
        ],
        __FILE__, __LINE__, undef, time(),
      );

      # Count the enqueued event.  This increments FMO_EV_COUNT
      # because an event has just been enqueued.  This makes sense.

      unless ($kr_fno_rec->[FMO_EV_COUNT]++) {
        my $handle = $select->[HSS_HANDLE];
        $self->loop_pause_filehandle($handle, $mode);
        $kr_fno_rec->[FMO_ST_ACTUAL] = HS_PAUSED;
      }

      if (TRACE_FILES) {
        _warn(
          "<fh> incremented event count in mode ($mode) ",
          "for fileno ($fileno) to count ($kr_fno_rec->[FMO_EV_COUNT])"
        );
      }
    }
  }
}

### Test whether POE is tracking a file handle.

sub _data_handle_is_good {
  my ($self, $handle, $mode) = @_;

  # Don't bother if the kernel isn't tracking the file.
  return 0 unless exists $kr_filenos{fileno $handle};

  # Don't bother if the kernel isn't tracking the file mode.
  return 0 unless $kr_filenos{fileno $handle}->[$mode]->[FMO_REFCOUNT];

  return 1;
}

### Add a select to the session, and possibly begin a watcher.

sub _data_handle_add {
  my ($self, $handle, $mode, $session, $event, $args) = @_;
  my $fd = fileno($handle);

  # First time watching the file descriptor.  Do some heavy setup.
  #
  # NB - This means we can't optimize away the delete() calls here and
  # there, because they probably ensure that the structure exists.
  unless (exists $kr_filenos{$fd}) {

    $kr_filenos{$fd} =
      [ [ 0,          # FMO_REFCOUNT    MODE_RD
          HS_PAUSED,  # FMO_ST_ACTUAL
          HS_PAUSED,  # FMO_ST_REQUEST
          0,          # FMO_EV_COUNT
          { },        # FMO_SESSIONS
        ],
        [ 0,          # FMO_REFCOUNT    MODE_WR
          HS_PAUSED,  # FMO_ST_ACTUAL
          HS_PAUSED,  # FMO_ST_REQUEST
          0,          # FMO_EV_COUNT
          { },        # FMO_SESSIONS
        ],
        [ 0,          # FMO_REFCOUNT    MODE_EX
          HS_PAUSED,  # FMO_ST_ACTUAL
          HS_PAUSED,  # FMO_ST_REQUEST
          0,          # FMO_EV_COUNT
          { },        # FMO_SESSIONS
        ],
        0,            # FNO_TOT_REFCOUNT
      ];

    if (TRACE_FILES) {
      _warn "<fh> adding fd ($fd) in mode ($mode)";
    }

    # For DOSISH systems like OS/2.  Wrapped in eval{} in case it's a
    # tied handle that doesn't support binmode.
    eval { binmode *$handle };

    # Turn off blocking unless it's tied or a plain file.
    unless (tied *$handle or -f $handle) {

      unless (RUNNING_IN_HELL) {
        if ($] >= 5.008) {
          $handle->blocking(0);
        }
        else {
          # Long, drawn out, POSIX way.
          my $flags = fcntl($handle, F_GETFL, 0)
            or _trap "fcntl($handle, F_GETFL, etc.) fails: $!\n";
          until (fcntl($handle, F_SETFL, $flags | O_NONBLOCK)) {
            _trap "fcntl($handle, FSETFL, etc) fails: $!"
              unless $! == EAGAIN or $! == EWOULDBLOCK;
          }
        }
      }
      else {
        # Do it the Win32 way.
        my $set_it = "1";

        # 126 is FIONBIO (some docs say 0x7F << 16)
        ioctl(
          $handle,
          0x80000000 | (4 << 16) | (ord('f') << 8) | 126,
          \$set_it
        ) or _trap(
          "ioctl($handle, FIONBIO, $set_it) fails: errno " . ($!+0) . " = $!\n"
        );
      }
    }

    # Turn off buffering.
    CORE::select((CORE::select($handle), $| = 1)[0]);
  }

  # Cache some high-level lookups.
  my $kr_fileno  = $kr_filenos{$fd};
  my $kr_fno_rec = $kr_fileno->[$mode];

  # The session is already watching this fileno in this mode.

  if ($kr_fno_rec->[FMO_SESSIONS]->{$session}) {

    # The session is also watching it by the same handle.  Treat this
    # as a "resume" in this mode.

    if (exists $kr_fno_rec->[FMO_SESSIONS]->{$session}->{$handle}) {
      if (TRACE_FILES) {
        _warn(
          "<fh> running fileno($fd) mode($mode) " .
          "count($kr_fno_rec->[FMO_EV_COUNT])"
        );
      }
      unless ($kr_fno_rec->[FMO_EV_COUNT]) {
        $self->loop_resume_filehandle($handle, $mode);
        $kr_fno_rec->[FMO_ST_ACTUAL] = HS_RUNNING;
      }
      $kr_fno_rec->[FMO_ST_REQUEST] = HS_RUNNING;
    }

    # The session is watching it by a different handle.  It can't be
    # done yet, but maybe later when drivers are added to the mix.
    #
    # TODO - This can occur if someone closes a filehandle without
    # calling select_foo() to deregister it from POE.  In that case,
    # the operating system reuses the file descriptor, but we still
    # have something registered for it here.

    else {
      foreach my $watch_session (keys %{$kr_fno_rec->[FMO_SESSIONS]}) {
        foreach my $hdl_rec (
          values %{$kr_fno_rec->[FMO_SESSIONS]->{$watch_session}}
        ) {
          my $other_handle = $hdl_rec->[HSS_HANDLE];

          my $why;
          unless (defined(fileno $other_handle)) {
            $why = "closed";
          }
          elsif (fileno($handle) == fileno($other_handle)) {
            $why = "open";
          }
          else {
            $why = "open with different file descriptor";
          }

          if ($session eq $watch_session) {
            _die(
              "A session was caught watching two different file handles that\n",
              "reference the same file descriptor in the same mode ($mode).\n",
              "This error is usually caused by a file descriptor leak.  The\n",
              "most common cause is explicitly closing a filehandle without\n",
              "first unregistering it from POE.\n",
              "\n",
              "Some possibly helpful information:\n",
              "  Session    : ", $self->_data_alias_loggable($session), "\n",
              "  Old handle : $other_handle (currently $why)\n",
              "  New handle : $handle\n",
              "\n",
              "Please correct the program and try again.\n",
            );
          }
          else {
            _die(
              "Two sessions were caught watching the same file descriptor\n",
              "in the same mode ($mode).  This error is usually caused by\n",
              "a file descriptor leak.  The most common cause is explicitly\n",
              "closing a filehandle without first unregistering it from POE.\n",
              "\n",
              "Some possibly helpful information:\n",
              "  Old session: ",
              $self->_data_alias_loggable($hdl_rec->[HSS_SESSION]), "\n",
              "  Old handle : $other_handle (currently $why)\n",
              "  New session: ", $self->_data_alias_loggable($session), "\n",
              "  New handle : $handle\n",
              "\n",
              "Please correct the program and try again.\n",
            );
          }
        }
      }
      _trap "internal inconsistency";
    }
  }

  # The session is not watching this fileno in this mode.  Record
  # the session/handle pair.

  else {
    $kr_fno_rec->[FMO_SESSIONS]->{$session}->{$handle} = [
      $handle,   # HSS_HANDLE
      $session,  # HSS_SESSION
      $event,    # HSS_STATE
      $args,     # HSS_ARGS
    ];

    # Fix reference counts.
    $kr_fileno->[FNO_TOT_REFCOUNT]++;
    $kr_fno_rec->[FMO_REFCOUNT]++;

    # If this is the first time a file is watched in this mode, then
    # have the event loop bridge watch it.

    if ($kr_fno_rec->[FMO_REFCOUNT] == 1) {
      $self->loop_watch_filehandle($handle, $mode);
      $kr_fno_rec->[FMO_ST_ACTUAL]  = HS_RUNNING;
      $kr_fno_rec->[FMO_ST_REQUEST] = HS_RUNNING;
    }
  }

  # If the session hasn't already been watching the filehandle, then
  # register the filehandle in the session's structure.

  unless (exists $kr_ses_to_handle{$session}->{$handle}) {
    $kr_ses_to_handle{$session}->{$handle} = [
      $handle,  # SH_HANDLE
      0,        # SH_REFCOUNT
      [ 0,      # SH_MODECOUNT / MODE_RD
        0,      # SH_MODECOUNT / MODE_WR
        0       # SH_MODECOUNT / MODE_EX
      ]
    ];
    $self->_data_ses_refcount_inc($session);
  }

  # Modify the session's handle structure's reference counts, so the
  # session knows it has a reason to live.

  my $ss_handle = $kr_ses_to_handle{$session}->{$handle};
  unless ($ss_handle->[SH_MODECOUNT]->[$mode]) {
    $ss_handle->[SH_MODECOUNT]->[$mode]++;
    $ss_handle->[SH_REFCOUNT]++;
  }
}

### Remove a select from the kernel, and possibly trigger the
### session's destruction.

sub _data_handle_remove {
  my ($self, $handle, $mode, $session) = @_;
  my $fd = fileno($handle);

  # Make sure the handle is deregistered with the kernel.

  if (exists $kr_filenos{$fd}) {
    my $kr_fileno  = $kr_filenos{$fd};
    my $kr_fno_rec = $kr_fileno->[$mode];

    # Make sure the handle was registered to the requested session.

    if (
      exists($kr_fno_rec->[FMO_SESSIONS]->{$session}) and
      exists($kr_fno_rec->[FMO_SESSIONS]->{$session}->{$handle})
    ) {

      TRACE_FILES and
        _warn "<fh> removing handle ($handle) fileno ($fd) mode ($mode)";

      # Remove the handle from the kernel's session record.

      my $handle_rec =
        delete $kr_fno_rec->[FMO_SESSIONS]->{$session}->{$handle};

      my $kill_session = $handle_rec->[HSS_SESSION];
      my $kill_event   = $handle_rec->[HSS_STATE];

      # Remove any events destined for that handle.  Decrement
      # FMO_EV_COUNT for each, because we've removed them.  This makes
      # sense.
      my $my_select = sub {
        return 0 unless $_[0]->[EV_TYPE]    &  ET_SELECT;
        return 0 unless $_[0]->[EV_SESSION] == $kill_session;
        return 0 unless $_[0]->[EV_NAME]    eq $kill_event;
        return 0 unless $_[0]->[EV_ARGS]->[EA_SEL_HANDLE] == $handle;
        return 0 unless $_[0]->[EV_ARGS]->[EA_SEL_MODE]   == $mode;
        return 1;
      };

      foreach ($kr_queue->remove_items($my_select)) {
        my ($time, $id, $event) = @$_;
        $self->_data_ev_refcount_dec( @$event[EV_SESSION, EV_SOURCE] );

        TRACE_EVENTS and
          _warn "<ev> removing select event $id ``$event->[EV_NAME]''";

        $kr_fno_rec->[FMO_EV_COUNT]--;

        if (TRACE_FILES) {
          _warn(
            "<fh> fileno $fd mode $mode event count went to ",
            $kr_fno_rec->[FMO_EV_COUNT]
          );
        }

        if (ASSERT_DATA) {
          _trap "<dt> fileno $fd mode $mode event count went below zero"
            if $kr_fno_rec->[FMO_EV_COUNT] < 0;
        }
      }

      # Decrement the handle's reference count.

      $kr_fno_rec->[FMO_REFCOUNT]--;

      if (ASSERT_DATA) {
        _trap "<dt> fileno mode refcount went below zero"
          if $kr_fno_rec->[FMO_REFCOUNT] < 0;
      }

      # If the "mode" count drops to zero, then stop selecting the
      # handle.

      unless ($kr_fno_rec->[FMO_REFCOUNT]) {
        $self->loop_ignore_filehandle($handle, $mode);
        $kr_fno_rec->[FMO_ST_ACTUAL]  = HS_STOPPED;
        $kr_fno_rec->[FMO_ST_REQUEST] = HS_STOPPED;

        # The session is not watching handles anymore.  Remove the
        # session entirely the fileno structure.
        delete $kr_fno_rec->[FMO_SESSIONS]->{$session}
          unless keys %{$kr_fno_rec->[FMO_SESSIONS]->{$session}};
      }

      # Decrement the kernel record's handle reference count.  If the
      # handle is done being used, then delete it from the kernel's
      # record structure.  This initiates Perl's garbage collection on
      # it, as soon as whatever else in "user space" frees it.

      $kr_fileno->[FNO_TOT_REFCOUNT]--;

      if (ASSERT_DATA) {
        _trap "<dt> fileno refcount went below zero"
          if $kr_fileno->[FNO_TOT_REFCOUNT] < 0;
      }

      unless ($kr_fileno->[FNO_TOT_REFCOUNT]) {
        if (TRACE_FILES) {
          _warn "<fh> deleting handle ($handle) fileno ($fd) entirely";
        }
        delete $kr_filenos{$fd};
      }
    }
    elsif (TRACE_FILES) {
      _warn(
        "<fh> session doesn't own handle ($handle) fileno ($fd) mode ($mode)"
      );
    }
  }
  elsif (TRACE_FILES) {
    _warn(
      "<fh> handle ($handle) fileno ($fd) is not registered with POE::Kernel"
    );
  }

  # SS_HANDLES - Remove the select from the session, assuming there is
  # a session to remove it from.  -><- Key it on fileno?

  if (
    exists($kr_ses_to_handle{$session}) and
    exists($kr_ses_to_handle{$session}->{$handle})
  ) {

    # Remove it from the session's read, write or expedite mode.

    my $ss_handle = $kr_ses_to_handle{$session}->{$handle};
    if ($ss_handle->[SH_MODECOUNT]->[$mode]) {

      # Hmm... what is this?  Was POE going to support multiple selects?

      $ss_handle->[SH_MODECOUNT]->[$mode] = 0;

      # Decrement the reference count, and delete the handle if it's done.

      $ss_handle->[SH_REFCOUNT]--;

      if (ASSERT_DATA) {
        _trap "<dt> refcount went below zero"
          if $ss_handle->[SH_REFCOUNT] < 0;
      }

      unless ($ss_handle->[SH_REFCOUNT]) {
        delete $kr_ses_to_handle{$session}->{$handle};
        $self->_data_ses_refcount_dec($session);
        delete $kr_ses_to_handle{$session}
          unless keys %{$kr_ses_to_handle{$session}};
      }
    }
    elsif (TRACE_FILES) {
      _warn(
        "<fh> handle ($handle) fileno ($fd) is not registered with",
        $self->_data_alias_loggable($session)
      );
    }
  }
}

### Resume a filehandle.  If there are no events in the queue for this
### handle/mode pair, then we go ahead and set the actual state now.
### Otherwise it must wait until the queue empties.

sub _data_handle_resume {
  my ($self, $handle, $mode) = @_;

  my $kr_fileno = $kr_filenos{fileno($handle)};
  my $kr_fno_rec = $kr_fileno->[$mode];

  if (TRACE_FILES) {
    _warn(
      "<fh> resume test: fileno(" . fileno($handle) . ") mode($mode) " .
      "count($kr_fno_rec->[FMO_EV_COUNT])"
    );
  }

  # Resume the handle if there are no events for it.
  unless ($kr_fno_rec->[FMO_EV_COUNT]) {
    $self->loop_resume_filehandle($handle, $mode);
    $kr_fno_rec->[FMO_ST_ACTUAL] = HS_RUNNING;
  }

  # Either way we set the handle's requested state to "running".
  $kr_fno_rec->[FMO_ST_REQUEST] = HS_RUNNING;
}

### Pause a filehandle.  If there are no events in the queue for this
### handle/mode pair, then we go ahead and set the actual state now.
### Otherwise it must wait until the queue empties.

sub _data_handle_pause {
  my ($self, $handle, $mode) = @_;

  my $kr_fileno = $kr_filenos{fileno($handle)};
  my $kr_fno_rec = $kr_fileno->[$mode];

  if (TRACE_FILES) {
    _warn(
      "<fh> pause test: fileno(" . fileno($handle) . ") mode($mode) " .
      "count($kr_fno_rec->[FMO_EV_COUNT])"
    );
  }

  unless ($kr_fno_rec->[FMO_EV_COUNT]) {
    $self->loop_pause_filehandle($handle, $mode);
    $kr_fno_rec->[FMO_ST_ACTUAL] = HS_PAUSED;
  }

  # Correct the requested state so it matches the actual one.

  $kr_fno_rec->[FMO_ST_REQUEST] = HS_PAUSED;
}

### Return the number of active filehandles in the entire system.

sub _data_handle_count {
  return scalar keys %kr_filenos;
}

### Return the number of active handles for a single session.

sub _data_handle_count_ses {
  my ($self, $session) = @_;
  return 0 unless exists $kr_ses_to_handle{$session};
  return scalar keys %{$kr_ses_to_handle{$session}};
}

### Clear all the handles owned by a session.

sub _data_handle_clear_session {
  my ($self, $session) = @_;
  return unless exists $kr_ses_to_handle{$session}; # avoid autoviv
  my @handles = values %{$kr_ses_to_handle{$session}};
  foreach (@handles) {
    my $handle = $_->[SH_HANDLE];
    my $refcount = $_->[SH_MODECOUNT];

    $self->_data_handle_remove($handle, MODE_RD, $session)
      if $refcount->[MODE_RD];
    $self->_data_handle_remove($handle, MODE_WR, $session)
      if $refcount->[MODE_WR];
    $self->_data_handle_remove($handle, MODE_EX, $session)
      if $refcount->[MODE_EX];
  }
}

# -><- Testing accessors.  Maybe useful for introspection.  May need
# modification before that.

sub _data_handle_fno_refcounts {
  my ($self, $fd) = @_;
  return(
    $kr_filenos{$fd}->[FNO_TOT_REFCOUNT],
    $kr_filenos{$fd}->[FNO_MODE_RD]->[FMO_REFCOUNT],
    $kr_filenos{$fd}->[FNO_MODE_WR]->[FMO_REFCOUNT],
    $kr_filenos{$fd}->[FNO_MODE_EX]->[FMO_REFCOUNT],
  )
}

sub _data_handle_fno_evcounts {
  my ($self, $fd) = @_;
  return(
    $kr_filenos{$fd}->[FNO_MODE_RD]->[FMO_EV_COUNT],
    $kr_filenos{$fd}->[FNO_MODE_WR]->[FMO_EV_COUNT],
    $kr_filenos{$fd}->[FNO_MODE_EX]->[FMO_EV_COUNT],
  )
}

sub _data_handle_fno_states {
  my ($self, $fd) = @_;
  return(
    $kr_filenos{$fd}->[FNO_MODE_RD]->[FMO_ST_ACTUAL],
    $kr_filenos{$fd}->[FNO_MODE_RD]->[FMO_ST_REQUEST],
    $kr_filenos{$fd}->[FNO_MODE_WR]->[FMO_ST_ACTUAL],
    $kr_filenos{$fd}->[FNO_MODE_WR]->[FMO_ST_REQUEST],
    $kr_filenos{$fd}->[FNO_MODE_EX]->[FMO_ST_ACTUAL],
    $kr_filenos{$fd}->[FNO_MODE_EX]->[FMO_ST_REQUEST],
  );
}

sub _data_handle_fno_sessions {
  my ($self, $fd) = @_;

  return(
    $kr_filenos{$fd}->[FNO_MODE_RD]->[FMO_SESSIONS],
    $kr_filenos{$fd}->[FNO_MODE_WR]->[FMO_SESSIONS],
    $kr_filenos{$fd}->[FNO_MODE_EX]->[FMO_SESSIONS],
  );
}

sub _data_handle_handles {
  my $self = shift;
  return %kr_ses_to_handle;
}

1;

__END__

=head1 NAME

POE::Resource::FileHandles - manage file handles on behalf of POE::Kernel

=head1 SYNOPSIS

Used internally by POE::Kernel.  Better documentation will be
forthcoming.

=head1 DESCRIPTION

This module encapsulates low-level file handle management for
POE::Kernel.  It provides accessors to its data structures that
POE::Kernel uses internally.  This module has no public interface.
Move along.

=head1 SEE ALSO

See L<POE::Kernel> for documentation on file handles and selects.

=head1 BUGS

Probably.

=head1 AUTHORS & COPYRIGHTS

Please see L<POE> for more information about authors and contributors.

=cut

require 'spec_helper_acceptance'

describe 'hocon_setting resource' do
  after :all do
    run_shell("rm #{os_tmpdir}/*.conf", acceptable_exit_codes: [0, 1, 2])
  end

  shared_examples 'has_content' do |path, pp, content|
    before :all do
      run_shell("rm #{path}", expect_failures: true)
    end

    it 'applies the manifest twice' do
      idempotent_apply(pp)
    end

    describe file(path) do
      it { is_expected.to be_file }
      # XXX Solaris 10 doesn't support multi-line grep
      it { is_expected.to contain(content) }
    end
  end

  shared_examples 'has_error' do |path, pp, error|
    before :all do
      run_shell("rm #{path}", expect_failures: true)
    end

    it 'applies the manifest and gets a failure message' do
      expect(apply_manifest(pp, expect_failures: true).stderr).to match(error)
    end

    describe file(path) do
      it { is_expected.not_to be_file }
    end
  end

  describe 'ensure parameter' do
    context '=> present for top-level and nested' do
      pp = <<-EOS
      hocon_setting { 'ensure => present for section':
        ensure  => present,
        path    => "#{os_tmpdir}/hocon_setting.conf",
        setting => 'one.two',
        value   => 'three',
      }
      hocon_setting { 'ensure => present for top level':
        ensure  => present,
        path    => "#{os_tmpdir}/hocon_setting.conf",
        setting => 'four',
        value   => 'five',
      }
      EOS

      it 'applies the manifest twice' do
        idempotent_apply(pp)
      end

      describe file("#{os_tmpdir}/hocon_setting.conf") do
        it { is_expected.to be_file }
        it("contains one {\n two=three\n}\nfour=five") {
          is_expected.to contain("one {\n    two=three\n}\nfour=five")
        }
      end
    end

    context '=> absent for key/value' do
      before :all do
        if os[:family] == 'Darwin'
          run_shell("echo \"one {\n    two=three\n}\nfour=five\" > #{os_tmpdir}/hocon_setting.conf")
        else
          run_shell("echo -e \"one {\n    two=three\n}\nfour=five\" > #{os_tmpdir}/hocon_setting.conf")
        end
      end

      pp = <<-EOS
      hocon_setting { 'ensure => absent for key/value':
        ensure  => absent,
        path    => "#{os_tmpdir}/hocon_setting.conf",
        setting => 'one.two',
        value   => 'three',
      }
      EOS

      it 'applies the manifest twice' do
        idempotent_apply(pp)
      end

      describe file("#{os_tmpdir}/hocon_setting.conf") do
        it { is_expected.to be_file }
        it { is_expected.to contain('four=five') }
        it { is_expected.not_to contain('two=three') }
      end
    end

    context '=> absent for top-level settings' do
      before :all do
        if os[:family] == 'Darwin'
          run_shell("echo \"one {\n    two=three\n}\nfour=five\" > #{os_tmpdir}/hocon_setting.conf")
        else
          run_shell("echo -e \"one {\n    two=three\n}\nfour=five\" > #{os_tmpdir}/hocon_setting.conf")
        end
      end
      after :all do
        run_shell("rm #{os_tmpdir}/hocon_setting.conf", acceptable_exit_codes: [0, 1, 2])
      end

      pp = <<-EOS
      hocon_setting { 'ensure => absent for top-level':
        ensure  => absent,
        path    => "#{os_tmpdir}/hocon_setting.conf",
        setting => 'four',
        value   => 'five',
      }
      EOS

      it 'applies the manifest twice' do
        idempotent_apply(pp)
      end

      describe file("#{os_tmpdir}/hocon_setting.conf") do
        it { is_expected.to be_file }
        it { is_expected.not_to contain('four=five') }
        it { is_expected.to contain("one {\n    two=three\n}") }
      end
    end
  end

  describe 'setting, value parameters' do
    {
      "setting => 'test.foo', value => 'bar',"   => "test {\n    foo = bar\n}",
      "setting => 'more.baz', value => 'quux',"  => "more {\n    baz = quux\n}",
      "setting => 'top', value => 'level',"      => 'top: "level"',
    }.each do |parameter_list, content|
      context parameter_list do
        pp = <<-EOS
        hocon_setting { "#{parameter_list}":
          ensure  => present,
          path    => "#{os_tmpdir}/hocon_setting.conf",
          #{parameter_list}
        }
        EOS

        it_behaves_like 'has_content', "#{os_tmpdir}/hocon_setting.conf", pp, content
      end
    end

    {
      ''                                     => %r{value is a required},
      "setting => 'test.foo',"               => %r{value is a required},
    }.each do |parameter_list, error|
      context parameter_list do
        pp = <<-EOS
        hocon_setting { "#{parameter_list}_setting":
          ensure  => present,
          path    => "#{os_tmpdir}/hocon_setting.conf",
          #{parameter_list}
        }
        EOS

        it_behaves_like 'has_error', "#{os_tmpdir}/hocon_setting.conf", pp, error
      end
    end
  end

  describe 'path parameter' do
    [
      "#{os_tmpdir}/one.conf",
      "#{os_tmpdir}/two.conf",
      "#{os_tmpdir}/three.conf",
    ].each do |path|
      context "path => #{path}" do
        pp = <<-EOS
        hocon_setting { 'path => #{path}':
          ensure  => present,
          setting => 'one.two',
          value   => 'three',
          path    => '#{path}',
        }
        EOS

        it_behaves_like 'has_content', path, pp, "one {\n    two=three\n}"
      end
    end

    context 'path => foo' do
      pp = <<-EOS
        hocon_setting { 'path => foo':
          ensure     => present,
          setting    => 'one.two',
          value      => 'three',
          path       => 'foo',
        }
      EOS

      it_behaves_like 'has_error', 'foo', pp, %r{must be fully qualified}
    end
  end

  describe 'path and setting parameters' do
    context 'path and setting must be unique' do
      pp = <<-EOS
      hocon_setting {'one.two':
        ensure => present,
        value => 'one',
        path => '#{os_tmpdir}/one.conf',
      }

      hocon_setting {'one.two2':
        setting => 'one.two',
        ensure => present,
        value => 'two',
        path => '#{os_tmpdir}/one.conf',
      }
      EOS

      it_behaves_like 'has_error', 'foo', pp, %r{Cannot alias}
    end

    context 'setting can be the same if path is different' do
      pp = <<-EOS
      hocon_setting {'one.two3':
        setting => 'one.two',
        ensure => present,
        value => 'one',
        path => '#{os_tmpdir}/four.conf',
      }

      hocon_setting {'one.two4':
        setting => 'one.two',
        ensure => present,
        value => 'two',
        path => '#{os_tmpdir}/five.conf',
      }
      EOS

      it_behaves_like 'has_content', "#{os_tmpdir}/four.conf", pp, "one {\n    two=one\n}"
      it_behaves_like 'has_content', "#{os_tmpdir}/five.conf", pp, "one {\n    two=two\n}"
    end
  end
end

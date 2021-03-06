require File.expand_path('../../../spec_helper', __FILE__)
require 'tmpdir'

module Pod
  describe Command::Trunk::Push do
    describe 'CLAide' do
      it 'registers it self' do
        Command.parse(%w(        trunk push        )).should.be.instance_of Command::Trunk::Push
      end
    end

    it "should error if we don't have a token" do
      Netrc.any_instance.stubs(:[]).returns(nil)
      command = Command.parse(%w( trunk push ))
      exception = lambda { command.validate! }.should.raise CLAide::Help
      exception.message.should.include 'register a session'
    end

    it 'should error when the trunk service returns an error' do
      url = 'https://trunk.cocoapods.org/api/v1/pods'
      WebMock::API.stub_request(:post, url).to_return(:status => 422, :body => {
        'error' => 'The Pod Specification did not pass validation.',
        'data' => {
          'warnings' => [
            'A value for `requires_arc` should be specified until the migration to a `true` default.',
          ],
        },
      }.to_json)
      command = Command.parse(%w(trunk push))
      command.stubs(:validate_podspec)
      command.stubs(:spec).returns(Pod::Specification.new)
      exception = lambda { command.run }.should.raise Informative
      exception.message.should.include 'following validation failed'
      exception.message.should.include 'should be specified'
      exception.message.should.include 'The Pod Specification did not pass validation'
    end

    describe 'PATH' do
      before do
        UI.output = ''
      end
      it 'defaults to the current directory' do
        # Disable the podspec finding algorithm so we can check the raw path
        Command::Trunk::Push.any_instance.stubs(:find_podspec_file) { |path| path }
        command = Command.parse(%w(        trunk push        ))
        command.instance_eval { @path }.should == '.'
      end

      def found_podspec_among_files(files)
        # Create a temp directory with the dummy `files` in it
        Dir.mktmpdir do |dir|
          files.each do |filename|
            path = Pathname(dir) + filename
            File.open(path, 'w') {}
          end
          # Execute `pod trunk push` with this dir as parameter
          command = Command.parse(%w(          trunk push          ) + [dir])
          path = command.instance_eval { @path }
          return File.basename(path) if path
        end
      end

      it 'should find the only JSON podspec in a given directory' do
        files = %w(foo bar.podspec.json baz)
        found_podspec_among_files(files).should == files[1]
      end

      it 'should find the only Ruby podspec in a given directory' do
        files = %w(foo bar.podspec baz)
        found_podspec_among_files(files).should == files[1]
      end

      it 'should warn when no podspec found in a given directory' do
        files = %w(foo bar baz)
        found_podspec_among_files(files).should.nil?
        UI.output.should.match /No podspec found in directory/
      end

      it 'should warn when multiple podspecs found in a given directory' do
        files = %w(foo bar.podspec bar.podspec.json baz)
        found_podspec_among_files(files).should.nil?
        UI.output.should.match /Multiple podspec files in directory/
      end
    end

    describe 'validation' do
      before do
        Installer.any_instance.stubs(:aggregate_targets).returns([])
        Installer.any_instance.stubs(:install!)

        Validator.any_instance.stubs(:check_file_patterns)
        Validator.any_instance.stubs(:validated?).returns(true)
        Validator.any_instance.stubs(:validate_url)
        Validator.any_instance.stubs(:validate_screenshots)
        Validator.any_instance.stubs(:xcodebuild).returns('')
      end

      it 'validates specs as frameworks by default' do
        Validator.any_instance.expects(:podfile_from_spec).with(:ios, nil, true).once
        Validator.any_instance.expects(:podfile_from_spec).with(:osx, nil, true).once

        cmd = Command.parse(%w(trunk push spec/fixtures/BananaLib.podspec))
        cmd.send(:validate_podspec)
      end

      it 'validates specs as libraries if requested' do
        Validator.any_instance.expects(:podfile_from_spec).with(:ios, nil, false).once
        Validator.any_instance.expects(:podfile_from_spec).with(:osx, nil, false).once

        cmd = Command.parse(%w(trunk push spec/fixtures/BananaLib.podspec --use-libraries))
        cmd.send(:validate_podspec)
      end
    end
  end
end
